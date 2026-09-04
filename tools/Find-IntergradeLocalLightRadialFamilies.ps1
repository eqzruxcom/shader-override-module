[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AssemblyDirectory,

    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\analysis\intergrade-local-light-radial-family-scan.json'),

    [string[]]$ExpectedHashes = @(),

    [switch]$RequireAtLeastOne
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$resolvedInput = (Resolve-Path -LiteralPath $AssemblyDirectory -ErrorAction Stop).Path
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $resolvedInput -PathType Container)) {
    throw "AssemblyDirectory not found: $AssemblyDirectory"
}
if (-not $resolvedOutput.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain beneath $artifacts"
}

function Normalize-DxbcLine {
    param([string]$Line)
    $value = $Line.Trim()
    $value = $value -replace '\s+\[precise(?:\([^\]]+\))?\]', ''
    $value = $value -replace '\s+', ' '
    return $value
}

function Test-Line {
    param(
        [string]$Line,
        [string]$Pattern
    )
    return [regex]::IsMatch($Line, $Pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

$files = @(Get-ChildItem -LiteralPath $resolvedInput -File -Filter '*-*.asm' | Sort-Object Name)
if ($files.Count -lt 1) { throw "No *-*.asm shader files found beneath $resolvedInput" }

$results = [Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    if ($file.BaseName -notmatch '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|hs|ds|gs)$') { continue }

    $hash = $Matches.hash.ToLowerInvariant()
    $stage = $Matches.stage.ToLowerInvariant()
    $raw = Get-Content -LiteralPath $file.FullName
    $lines = @($raw | ForEach-Object { Normalize-DxbcLine $_ })
    $text = $lines -join "`n"

    $bindingChecks = [ordered]@{
        shaderModelCs50 = Test-Line $text '(?m)^cs_5_0$'
        cb3Dynamic1024 = Test-Line $text '(?m)^dcl_constantbuffer CB3\[1024\], dynamicIndexed$'
        cb4Dynamic768 = Test-Line $text '(?m)^dcl_constantbuffer CB4\[768\], dynamicIndexed$'
        typedTexture2dUav0 = Test-Line $text '(?m)^dcl_uav_typed_texture2d \(float,float,float,float\) u0$'
        threadGroup16x16x1 = Test-Line $text '(?m)^dcl_thread_group 16, 16, 1$'
    }
    $bindingsCompatible = -not ($bindingChecks.Values -contains $false)

    $dynamicPositionRead = Test-Line $text '(?m)^add r\d+\.xyz, -r\d+\.yzwy, cb4\[r\d+\.[xyzw] \+ 0\]\.xyzx$'
    $dynamicInverseRadiusRead = Test-Line $text '(?m)^mul r\d+\.[xyzw], cb4\[r\d+\.[xyzw] \+ 0\]\.w, cb4\[r\d+\.[xyzw] \+ 0\]\.w$'

    $blocks = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $radiusPattern = '^mul (?<atten>r\d+\.[xyzw]), cb4\[(?<index>r\d+\.[xyzw]) \+ 0\]\.w, cb4\[\k<index> \+ 0\]\.w$'
        $radiusMatch = [regex]::Match($line, $radiusPattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $radiusMatch.Success) { continue }

        $atten = $radiusMatch.Groups['atten'].Value
        $index = $radiusMatch.Groups['index'].Value
        $distance = $null
        $polynomialCompatible = $false
        if ($i + 4 -lt $lines.Count) {
            $distanceMatch = [regex]::Match($lines[$i + 1], ('^mul ' + [regex]::Escape($atten) + ', (?<distance>r\d+\.[xyzw]), ' + [regex]::Escape($atten) + '$'))
            if ($distanceMatch.Success) {
                $distance = $distanceMatch.Groups['distance'].Value
                $one = 'l\(1(?:\.0+)?\)'
                $zero = 'l\(0(?:\.0+)?\)'
                $polynomialCompatible =
                    (Test-Line $lines[$i + 2] ('^mad ' + [regex]::Escape($atten) + ', -' + [regex]::Escape($atten) + ', ' + [regex]::Escape($atten) + ', ' + $one + '$')) -and
                    (Test-Line $lines[$i + 3] ('^max ' + [regex]::Escape($atten) + ', ' + [regex]::Escape($atten) + ', ' + $zero + '$')) -and
                    (Test-Line $lines[$i + 4] ('^mul ' + [regex]::Escape($atten) + ', ' + [regex]::Escape($atten) + ', ' + [regex]::Escape($atten) + '$'))
            }
        }

        $windowStart = [Math]::Max(0, $i - 14)
        $window = @($lines[$windowStart..$i])
        $positionCompatible = $false
        $distanceCompatible = $false
        $directionalParameterCompatible = $false
        foreach ($windowLine in $window) {
            $positionPattern = '^add (?<vector>r\d+)\.xyz, -r\d+\.yzwy, cb4\[' + [regex]::Escape($index) + ' \+ 0\]\.xyzx$'
            $positionMatch = [regex]::Match($windowLine, $positionPattern)
            if ($positionMatch.Success) {
                $positionCompatible = $true
                $vector = $positionMatch.Groups['vector'].Value
                foreach ($candidateLine in $window) {
                    if ($null -ne $distance -and (Test-Line $candidateLine ('^dp3 ' + [regex]::Escape($distance) + ', ' + [regex]::Escape($vector) + '\.xyzx, ' + [regex]::Escape($vector) + '\.xyzx$'))) {
                        $distanceCompatible = $true
                    }
                }
            }
            if (Test-Line $windowLine ('^ne r\d+\.[xyzw], l\(0(?:\.0+)?\), cb4\[' + [regex]::Escape($index) + ' \+ 512\]\.w$')) {
                $directionalParameterCompatible = $true
            }
        }

        $blocks.Add([pscustomobject][ordered]@{
            line = $i + 1
            lightIndexRegister = $index
            attenuationRegister = $atten
            distanceSquaredRegister = $distance
            positionReconstruction = $positionCompatible
            distanceSquared = $distanceCompatible
            inverseRadiusSquared = $true
            nativeCutoffPolynomial = $polynomialCompatible
            lightTypeBypassParameter = $directionalParameterCompatible
            compatible = $positionCompatible -and $distanceCompatible -and $polynomialCompatible -and $directionalParameterCompatible
        })
    }

    $compatibleBlocks = @($blocks | Where-Object compatible)
    $classification = if ($stage -ne 'cs') {
        'not-compute'
    } elseif ($compatibleBlocks.Count -eq 1 -and $bindingsCompatible) {
        'compatible-local-light-radial-family'
    } elseif ($blocks.Count -gt 0 -or $dynamicPositionRead -or $dynamicInverseRadiusRead) {
        'local-light-structural-exception'
    } else {
        'not-local-light-radial-family'
    }

    $results.Add([pscustomobject][ordered]@{
        shader = $file.BaseName
        hash = $hash
        stage = $stage
        file = $file.FullName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToUpperInvariant()
        classification = $classification
        bindingChecks = $bindingChecks
        bindingsCompatible = $bindingsCompatible
        dynamicPositionRead = $dynamicPositionRead
        dynamicInverseRadiusRead = $dynamicInverseRadiusRead
        radialBlockCount = $blocks.Count
        compatibleRadialBlockCount = $compatibleBlocks.Count
        radialBlocks = @($blocks)
    })
}

$matches = @($results | Where-Object classification -eq 'compatible-local-light-radial-family')
$exceptions = @($results | Where-Object classification -eq 'local-light-structural-exception')
$expected = @($ExpectedHashes | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
$actual = @($matches.hash | Sort-Object -Unique)
$missingExpected = @($expected | Where-Object { $_ -notin $actual })
$unexpected = @($actual | Where-Object { $expected.Count -gt 0 -and $_ -notin $expected })

$report = [ordered]@{
    schemaVersion = 1
    detector = 'ff7-remake-dxbc-local-light-radial-semantic-v1'
    sourceDirectory = $resolvedInput
    sourceShaderCount = $results.Count
    stageCounts = [ordered]@{
        vs = @($results | Where-Object stage -eq 'vs').Count
        ps = @($results | Where-Object stage -eq 'ps').Count
        cs = @($results | Where-Object stage -eq 'cs').Count
        hs = @($results | Where-Object stage -eq 'hs').Count
        ds = @($results | Where-Object stage -eq 'ds').Count
        gs = @($results | Where-Object stage -eq 'gs').Count
    }
    compatibleMatchCount = $matches.Count
    structuralExceptionCount = $exceptions.Count
    expectedHashes = $expected
    actualCompatibleHashes = $actual
    expectedSetMatches = ($expected.Count -eq 0 -or ($missingExpected.Count -eq 0 -and $unexpected.Count -eq 0))
    missingExpectedHashes = $missingExpected
    unexpectedCompatibleHashes = $unexpected
    compatibleMatches = $matches
    structuralExceptions = $exceptions
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path $resolvedOutput -Parent))
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8

if ($RequireAtLeastOne -and $matches.Count -lt 1) { throw 'No compatible local-light radial family was found.' }
if ($expected.Count -gt 0 -and ($missingExpected.Count -gt 0 -or $unexpected.Count -gt 0)) {
    throw "Compatible hash set differed from expectation. Missing: $($missingExpected -join ', '); unexpected: $($unexpected -join ', ')"
}

Write-Host "PASS: scanned $($results.Count) shaders; compatible=$($matches.Count); structural exceptions=$($exceptions.Count)."
Write-Host "Report: $resolvedOutput"

