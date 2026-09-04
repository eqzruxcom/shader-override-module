[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$ConstantMapPath,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RequiredFile {
    param([string]$Path, [string]$Label)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label was not found: $Path" }
    return $resolved
}

function Format-AssemblyFloat {
    param([double]$Value)
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        throw "Non-finite controller values cannot be baked into assembly: $Value"
    }
    return $Value.ToString('0.0################', [Globalization.CultureInfo]::InvariantCulture)
}

$source = Resolve-RequiredFile $SourcePath '3Dmigoto assembly source'
$mapPath = Resolve-RequiredFile $ConstantMapPath 'Texture constant map'
$map = Get-Content -Raw -LiteralPath $mapPath | ConvertFrom-Json
if ($map.schemaVersion -ne 1 -or $map.kind -ne 'migoto-texture1d-constant-map') {
    throw 'Constant map must be schemaVersion 1 and kind migoto-texture1d-constant-map.'
}
$resource = [string]$map.resource
if ($resource -notmatch '^t(?:[0-9]|[1-9][0-9]{1,2})$') { throw "Invalid texture register in constant map: $resource" }

$entries = @{}
foreach ($property in $map.entries.PSObject.Properties) {
    if ($property.Name -notmatch '^[0-9]+$') { throw "Invalid texture constant index: $($property.Name)" }
    $values = @($property.Value)
    if ($values.Count -ne 4) { throw "Texture constant index $($property.Name) must provide exactly four values." }
    $entries[[int]$property.Name] = @($values | ForEach-Object { [double]$_ })
}
if ($entries.Count -eq 0) { throw 'Texture constant map has no entries.' }

$declarationPattern = '^\s*dcl_resource_texture1d\s+\([^\r\n]+\)\s+' + [regex]::Escape($resource) + '\s*$'
$loadPattern = '^(?<indent>\s*)ld_indexable(?:\s+\[[^\]]+\])?\(texture1d\)\(float,float,float,float\)\s+(?<destination>r[0-9]+\.(?<mask>[xyzw]+)),\s*l\((?<index>[0-9]+),\s*0,\s*0,\s*0\),\s*' + [regex]::Escape($resource) + '\.(?<swizzle>[xyzw]{4})\s*$'
$componentIndex = @{ x=0; y=1; z=2; w=3 }
$sourceLines = [IO.File]::ReadAllLines($source)
$outputLines = [Collections.Generic.List[string]]::new()
$declarationsRemoved = 0
$loadsReplaced = 0
$replacementRecords = [Collections.Generic.List[object]]::new()

for ($lineNumber = 1; $lineNumber -le $sourceLines.Length; $lineNumber++) {
    $line = $sourceLines[$lineNumber - 1]
    if ([regex]::IsMatch($line, $declarationPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $outputLines.Add("// DXVK specialization: removed 3Dmigoto-only $resource declaration; reads are baked below.")
        $declarationsRemoved++
        continue
    }
    $match = [regex]::Match($line, $loadPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        $index = [int]$match.Groups['index'].Value
        if (-not $entries.ContainsKey($index)) {
            throw "No baked value exists for $resource index $index (source line $lineNumber)."
        }
        $mask = $match.Groups['mask'].Value.ToLowerInvariant()
        $swizzle = $match.Groups['swizzle'].Value.ToLowerInvariant()
        $literal = @(0.0, 0.0, 0.0, 0.0)
        foreach ($component in $mask.ToCharArray()) {
            $destinationIndex = $componentIndex[[string]$component]
            $sourceComponent = [string]$swizzle[$destinationIndex]
            $sourceIndex = $componentIndex[$sourceComponent]
            $literal[$destinationIndex] = $entries[$index][$sourceIndex]
        }
        $formatted = ($literal | ForEach-Object { Format-AssemblyFloat $_ }) -join ', '
        $replacement = "$($match.Groups['indent'].Value)mov $($match.Groups['destination'].Value), l($formatted)"
        $outputLines.Add($replacement)
        $replacementRecords.Add([ordered]@{
            sourceLine = $lineNumber
            index = $index
            destination = $match.Groups['destination'].Value
            sourceSwizzle = $swizzle
            replacement = $replacement.Trim()
        })
        $loadsReplaced++
        continue
    }
    if ($line -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($resource) + '(?![A-Za-z0-9_])')) {
        throw "Unsupported $resource use remains at source line ${lineNumber}: $line"
    }
    $outputLines.Add($line)
}

if ($declarationsRemoved -ne 1) { throw "Expected exactly one $resource texture1d declaration, found $declarationsRemoved." }
if ($loadsReplaced -eq 0) { throw "No $resource texture1d loads were specialized." }

$output = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $output
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$manifestPath = $output + '.specialization.json'
$temporary = $output + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$temporaryManifest = $manifestPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$utf8 = [Text.UTF8Encoding]::new($false)

try {
    [IO.File]::WriteAllLines($temporary, $outputLines, $utf8)
    $outputSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        schemaVersion = 1
        kind = 'dxvk-migoto-texture-constant-specialization'
        sourcePath = $source
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
        constantMapPath = $mapPath
        constantMapSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $mapPath).Hash.ToLowerInvariant()
        resource = $resource
        declarationsRemoved = $declarationsRemoved
        loadsReplaced = $loadsReplaced
        replacements = @($replacementRecords)
        outputPath = $output
        outputSha256 = $outputSha
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        runtimeEligible = $false
        installed = $false
    }
    [IO.File]::WriteAllText($temporaryManifest, (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $utf8)

    $outputExists = Test-Path -LiteralPath $output -PathType Leaf
    $manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
    if ($outputExists -or $manifestExists) {
        if (-not ($outputExists -and $manifestExists)) { throw 'Refusing to overwrite incomplete prior specialization evidence.' }
        $existing = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $existingSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
        if ($existing.outputSha256 -ne $existingSha -or $existingSha -ne $outputSha -or
            $existing.sourceSha256 -ne $manifest.sourceSha256 -or
            $existing.constantMapSha256 -ne $manifest.constantMapSha256 -or
            $existing.resource -ne $resource) {
            throw 'Refusing to overwrite mismatched prior specialization evidence. Use a new output path.'
        }
        Write-Host "PASS: existing DXVK specialization is identical: $output"
        return
    }

    Move-Item -LiteralPath $temporary -Destination $output
    try { Move-Item -LiteralPath $temporaryManifest -Destination $manifestPath }
    catch {
        if (Test-Path -LiteralPath $output -PathType Leaf) { Remove-Item -LiteralPath $output -Force }
        throw
    }
    Write-Host "PASS: baked $loadsReplaced $resource reads and removed the 3Dmigoto-only binding."
    Write-Host "Assembly: $output"
    Write-Host "Manifest: $manifestPath"
}
finally {
    foreach ($path in @($temporary, $temporaryManifest)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}
