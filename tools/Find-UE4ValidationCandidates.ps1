[CmdletBinding()]
param(
    [string[]]$GameDirectory,
    [string[]]$SearchRoot = @(
        'C:\Games',
        'D:\Games',
        'F:\Games',
        'C:\Program Files (x86)\Steam\steamapps\common'
    ),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-validation-candidates.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-OutputPath([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) {
        [IO.Path]::GetFullPath($Path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath must remain inside the project workspace: $full"
    }
    $full
}

function Get-RelativeEvidencePath([string]$Root, [string]$Path) {
    if ($Path.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Root.Length + 1).Replace('\', '/')
    }
    $Path.Replace('\', '/')
}

function Add-Evidence([Collections.Generic.List[string]]$List, [string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value)
    }
}

function Get-ManifestEvidence([string]$Root) {
    $unreal = [Collections.Generic.List[string]]::new()
    $sm5 = [Collections.Generic.List[string]]::new()
    $sm6 = [Collections.Generic.List[string]]::new()

    foreach ($manifest in @(Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Manifest_.*Files.*\.txt$' })) {
        $lineNumber = 0
        foreach ($line in [IO.File]::ReadLines($manifest.FullName)) {
            $lineNumber++
            if ($line -match '(?i)(?:^|[/\\])Engine[/\\]|ShaderArchive-|GlobalShaderCache-') {
                Add-Evidence $unreal "manifest:$($manifest.Name)#$lineNumber"
            }
            if ($line -match '(?i)PCD3D_SM5') {
                Add-Evidence $sm5 "manifest:$($manifest.Name)#$lineNumber"
            }
            if ($line -match '(?i)PCD3D_SM6') {
                Add-Evidence $sm6 "manifest:$($manifest.Name)#$lineNumber"
            }
        }
    }

    [pscustomobject]@{
        unreal = @($unreal)
        sm5 = @($sm5)
        sm6 = @($sm6)
    }
}

function Get-DirectShaderCacheEvidence([string]$Root) {
    $sm5 = [Collections.Generic.List[string]]::new()
    $sm6 = [Collections.Generic.List[string]]::new()
    $patterns = @(
        (Join-Path $Root 'Engine\GlobalShaderCache-PCD3D_SM*.bin'),
        (Join-Path $Root '*\Content\ShaderArchive*PCD3D_SM*'),
        (Join-Path $Root '*\Content\ShaderTypeInfo*PCD3D_SM*')
    )
    foreach ($pattern in $patterns) {
        foreach ($file in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)) {
            $relative = Get-RelativeEvidencePath $Root $file.FullName
            if ($file.Name -match '(?i)PCD3D_SM5') { Add-Evidence $sm5 $relative }
            if ($file.Name -match '(?i)PCD3D_SM6') { Add-Evidence $sm6 $relative }
        }
    }
    [pscustomobject]@{ sm5 = @($sm5); sm6 = @($sm6) }
}

if (-not $GameDirectory -or -not @($GameDirectory).Count) {
    $discovered = [Collections.Generic.List[string]]::new()
    foreach ($root in $SearchRoot) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if (-not $discovered.Contains($directory.FullName)) { $discovered.Add($directory.FullName) }
        }
    }
    $GameDirectory = @($discovered)
}

$candidates = foreach ($inputPath in @($GameDirectory | Sort-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $inputPath -PathType Container)) { continue }
    $root = (Resolve-Path -LiteralPath $inputPath).Path.TrimEnd('\')
    $unrealEvidence = [Collections.Generic.List[string]]::new()
    $sm5Evidence = [Collections.Generic.List[string]]::new()
    $sm6Evidence = [Collections.Generic.List[string]]::new()
    $otherEngineEvidence = [Collections.Generic.List[string]]::new()
    $dx11Evidence = [Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath (Join-Path $root 'Engine') -PathType Container) {
        Add-Evidence $unrealEvidence 'Engine/'
    }
    foreach ($child in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $child.FullName 'Content\Paks') -PathType Container) {
            Add-Evidence $unrealEvidence "$($child.Name)/Content/Paks/"
        }
        if ($child.Name -match '_Data$') { Add-Evidence $otherEngineEvidence "$($child.Name)/ (Unity layout)" }
    }
    if (Test-Path -LiteralPath (Join-Path $root 'UnityPlayer.dll') -PathType Leaf) {
        Add-Evidence $otherEngineEvidence 'UnityPlayer.dll'
    }

    $manifest = Get-ManifestEvidence $root
    foreach ($value in $manifest.unreal) { Add-Evidence $unrealEvidence $value }
    foreach ($value in $manifest.sm5) { Add-Evidence $sm5Evidence $value }
    foreach ($value in $manifest.sm6) { Add-Evidence $sm6Evidence $value }

    $direct = Get-DirectShaderCacheEvidence $root
    foreach ($value in $direct.sm5) { Add-Evidence $sm5Evidence $value }
    foreach ($value in $direct.sm6) { Add-Evidence $sm6Evidence $value }

    $ff7Exe = Join-Path $root 'End\Binaries\Win64\ff7remake_.exe'
    $ff7D3D11 = Join-Path $root 'End\Binaries\Win64\d3d11.dll'
    $ff7ShaderFixes = Join-Path $root 'End\Binaries\Win64\ShaderFixes'
    $isCurrentProof = (Test-Path -LiteralPath $ff7Exe -PathType Leaf) -and
        (Test-Path -LiteralPath $ff7D3D11 -PathType Leaf)
    if ($isCurrentProof) {
        Add-Evidence $unrealEvidence 'End/Binaries/Win64/ff7remake_.exe'
        Add-Evidence $dx11Evidence 'End/Binaries/Win64/d3d11.dll'
        if (Test-Path -LiteralPath $ff7ShaderFixes -PathType Container) {
            Add-Evidence $dx11Evidence 'End/Binaries/Win64/ShaderFixes/'
        }
    }

    $isUnreal = @($unrealEvidence).Count -gt 0
    $hasSm5 = @($sm5Evidence).Count -gt 0
    $hasSm6 = @($sm6Evidence).Count -gt 0
    $classification = if ($isCurrentProof) {
        'current-proof-adapter'
    } elseif (-not $isUnreal) {
        'excluded-no-unreal-evidence'
    } elseif ($hasSm5) {
        'eligible-dx11-sm5-candidate'
    } elseif ($hasSm6) {
        'excluded-sm6-only'
    } else {
        'manual-shader-model-evidence-required'
    }

    [pscustomobject]@{
        name = Split-Path -Leaf $root
        path = $root
        classification = $classification
        eligibleForDx11Sm5Validation = $classification -in @('current-proof-adapter', 'eligible-dx11-sm5-candidate')
        evidence = [ordered]@{
            unreal = @($unrealEvidence)
            shaderModel5 = @($sm5Evidence)
            shaderModel6 = @($sm6Evidence)
            dx11Proof = @($dx11Evidence)
            otherEngine = @($otherEngineEvidence)
        }
    }
}

$classificationCounts = foreach ($group in @($candidates | Group-Object classification | Sort-Object Name)) {
    [pscustomobject]@{ classification = $group.Name; count = $group.Count }
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    policy = [ordered]@{
        target = 'Unreal Engine DX11 Shader Model 5'
        failClosed = $true
        note = 'An Unreal layout alone is not SM5 proof. SM6-only installs are excluded.'
    }
    scannedGameCount = @($candidates).Count
    eligibleAdditionalGameCount = @($candidates | Where-Object classification -eq 'eligible-dx11-sm5-candidate').Count
    classificationCounts = @($classificationCounts)
    games = @($candidates | Sort-Object path)
}

$outputFull = Resolve-OutputPath $OutputPath
$outputDirectory = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

Write-Output "Wrote $outputFull"
Write-Output "Scanned games: $(@($candidates).Count)"
Write-Output "Additional DX11/SM5 candidates: $($report.eligibleAdditionalGameCount)"
foreach ($candidate in @($candidates | Sort-Object path)) {
    Write-Output "$($candidate.classification)`t$($candidate.path)"
}
