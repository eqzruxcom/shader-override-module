[CmdletBinding()]
param(
    [string]$RuntimeRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\Intergrade\Mods'),
    [string]$IntegrationManifest = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-rebirth-fallback-consumer-f2-owner-integration-pack\manifest.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\agent2-ao-control-ownership.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')

function Resolve-WorkspacePath([string]$Path, [switch]$AllowMissing, [switch]$Directory) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $Path)) }
    if (-not $full.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path must remain inside the project workspace: $full" }
    if (-not $AllowMissing) {
        $type = if ($Directory) { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $full -PathType $type)) { throw "Required path does not exist: $full" }
    }
    $full
}
function Relative-Path([string]$Path) { $Path.Substring($repoRoot.Length + 1).Replace('\','/') }

$runtimeFull = Resolve-WorkspacePath $RuntimeRoot -Directory
$integrationFull = Resolve-WorkspacePath $IntegrationManifest
$outputFull = Resolve-WorkspacePath $OutputPath -AllowMissing
$iniFiles = @(Get-ChildItem -LiteralPath $runtimeFull -Recurse -File -Filter '*.ini' | Sort-Object FullName)

$keyClaims = [Collections.Generic.List[object]]::new()
$e2aaClaims = [Collections.Generic.List[object]]::new()
foreach ($ini in $iniFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $ini.FullName) {
        $lineNumber++
        if ($line -match '^\s*;') { continue }
        $keyMatch = [regex]::Match($line, '(?i)^\s*key\s*=.*(?<![A-Z0-9_])(?:VK_)?F(?<number>[123])(?![A-Z0-9_]).*$')
        if ($keyMatch.Success) {
            $keyClaims.Add([ordered]@{ key='F'+$keyMatch.Groups['number'].Value; ini=Relative-Path $ini.FullName; line=$lineNumber; text=$line.Trim() })
        }
        if ($line -match '(?i)^\s*hash\s*=\s*e2aa1c8cb39e0a55\s*$') {
            $e2aaClaims.Add([ordered]@{ ini=Relative-Path $ini.FullName; line=$lineNumber; text=$line.Trim() })
        }
    }
}

$ownerPath = Join-Path $runtimeFull 'RebirthEffectsDX11.ini'
if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) { throw 'Expected e2aa owner INI is missing.' }
$ownerText = [IO.File]::ReadAllText($ownerPath)
$ownerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ownerPath).Hash
$ownerBody = [regex]::Match($ownerText, '(?ms)\[ShaderOverrideRebirthABShared\].*?if \$rebirth_ab_current == 0\r?\n\s+run = (?<previous>[A-Za-z0-9_]+)\r?\nelse\r?\n\s+run = (?<current>[A-Za-z0-9_]+)\r?\nendif')
if (-not $ownerBody.Success) { throw 'Existing e2aa owner body changed.' }

$integration = Get-Content -Raw -LiteralPath $integrationFull | ConvertFrom-Json
if ($integration.shaderHash -ne 'e2aa1c8cb39e0a55' -or $integration.status -ne 'offline-owner-integration-preview-not-installed') {
    throw 'Integration preview manifest contract changed.'
}
$integrationOwnerMatches = $integration.existingOwner.exactSha256 -eq $ownerSha256
$patchedIni = Resolve-WorkspacePath $integration.patchedIni
$patchedShader = Resolve-WorkspacePath $integration.shader
$integrationHashesMatch =
    ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchedIni).Hash -eq $integration.patchedIniSha256) -and
    ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchedShader).Hash -eq $integration.shaderSha256)

$variantConflicts = [Collections.Generic.List[object]]::new()
$variantRoot = Join-Path $repoRoot 'artifacts\ao-rebirth-fallback-consumer-variants'
if (Test-Path -LiteralPath $variantRoot -PathType Container) {
    foreach ($variantPath in Get-ChildItem -LiteralPath $variantRoot -File -Filter '*.json' | Sort-Object Name) {
        $variant = Get-Content -Raw -LiteralPath $variantPath.FullName | ConvertFrom-Json
        if ($null -ne $variant.reservedAOControls) {
            $conflict = $variant.reservedAOControls.F1 -ne 'future global mod on/off' -or
                $variant.reservedAOControls.F2 -ne 'binary native/candidate test toggle' -or
                $variant.reservedAOControls.F3 -ne 'not AO-owned'
            if ($conflict) {
                $variantConflicts.Add([ordered]@{
                    manifest = Relative-Path $variantPath.FullName
                    preset = $variant.preset
                    embeddedMapping = [ordered]@{ F1=$variant.reservedAOControls.F1; F2=$variant.reservedAOControls.F2; F3=$variant.reservedAOControls.F3 }
                    classification = 'non-authoritative control metadata'
                })
            }
        }
    }
}

$f1Claims = @($keyClaims | Where-Object key -eq 'F1')
$f2Claims = @($keyClaims | Where-Object key -eq 'F2')
$f3Claims = @($keyClaims | Where-Object key -eq 'F3')
$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    authoritativeControlContract = [ordered]@{
        F1 = 'future global mod on/off; AO must not claim it'
        F2 = 'single binary shader-change test toggle; off preserves existing owner, on runs current candidate'
        F3 = 'not AO-owned; preserve current rolling A/B until separately resolved'
    }
    runtime = [ordered]@{
        root = Relative-Path $runtimeFull
        iniFilesScanned = $iniFiles.Count
        F1Claims = @($f1Claims)
        F2Claims = @($f2Claims)
        F3Claims = @($f3Claims)
        e2aaClaims = @($e2aaClaims)
        owner = [ordered]@{
            ini = Relative-Path $ownerPath
            sha256 = $ownerSha256
            section = 'ShaderOverrideRebirthABShared'
            previousCustom = $ownerBody.Groups['previous'].Value
            currentCustom = $ownerBody.Groups['current'].Value
            bothBranchesIdentical = $ownerBody.Groups['previous'].Value -eq $ownerBody.Groups['current'].Value
        }
    }
    integrationPreview = [ordered]@{
        manifest = Relative-Path $integrationFull
        exactOwnerMatchesCurrent = $integrationOwnerMatches
        hashesMatch = $integrationHashesMatch
        singleOwnerDesign = $integration.singleOwnerContract.e2aaOverrideCount -eq 1 -and $integration.singleOwnerContract.duplicateOverrideAdded -eq $false
        offlineReady = $integrationOwnerMatches -and $integrationHashesMatch
        installed = $false
        liveStageReady = $false
        liveStageBlockers = @('explicit staging authorization not provided','live visual validation pending','current F3 rolling A/B purpose must remain preserved or be separately resolved')
    }
    nonAuthoritativeVariantControlMetadata = @($variantConflicts)
    assertions = [ordered]@{
        AOClaimsF1Now = $false
        AOClaimsF2Now = $false
        currentRuntimeF1ClaimCount = $f1Claims.Count
        currentRuntimeF2ClaimCount = $f2Claims.Count
        currentRuntimeF3ClaimCount = $f3Claims.Count
        currentRuntimeE2aaOwnerCount = $e2aaClaims.Count
        conflictingVariantManifestCount = $variantConflicts.Count
    }
}
if ($f1Claims.Count -ne 0 -or $f2Claims.Count -ne 0) { throw 'Current runtime unexpectedly claims reserved F1 or F2.' }
if ($f3Claims.Count -ne 1 -or $e2aaClaims.Count -ne 1) { throw 'Current F3/e2aa owner topology changed.' }
if (-not $integrationOwnerMatches -or -not $integrationHashesMatch) { throw 'Offline integration preview is stale or corrupt.' }

New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force | Out-Null
[IO.File]::WriteAllText($outputFull, (($report | ConvertTo-Json -Depth 14) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Output "Intergrade Agent 2 AO control-ownership audit passed: $outputFull"
