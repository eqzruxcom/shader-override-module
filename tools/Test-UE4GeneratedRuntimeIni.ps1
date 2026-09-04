[CmdletBinding()]
param(
    [string]$GeneratedRuntimeDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\generated-runtime\FF7RemakeIntergrade'),
    [string]$LiveModsDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\Mods'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$generatedRoot = (Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
$modsRoot = Join-Path $generatedRoot 'Mods'
$iniPath = Join-Path $modsRoot 'UE4EffectsGenerated.ini'
$manifestPath = Join-Path $generatedRoot 'runtime-manifest.json'
if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw "Generated INI is missing: $iniPath" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Generated runtime manifest is missing: $manifestPath" }

$ini = [IO.File]::ReadAllText($iniPath)
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$sectionMatches = [regex]::Matches($ini, '(?m)^\[([^\]\r\n]+)\]\s*$')
$sections = @($sectionMatches | ForEach-Object { $_.Groups[1].Value })
$duplicateSections = @($sections | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1)
if ($duplicateSections.Count) { throw "Duplicate generated INI section: $($duplicateSections[0].Name)" }
if (@($sections | Where-Object { $_ -ieq 'Constants' }).Count -ne 1) { throw 'Generated INI must contain exactly one Constants section.' }

$definedVariables = @([regex]::Matches($ini, '(?m)^global\s+(\$[A-Za-z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
$usedVariables = @([regex]::Matches($ini, '\$ue4fx_[A-Za-z0-9_]+') | ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique)
foreach ($variable in $usedVariables) {
    if ($definedVariables -notcontains $variable) { throw "Generated INI references an undefined variable: $variable" }
}
if ($definedVariables.Count -ne @($manifest.controls).Count) { throw 'Generated variable count does not match runtime controls.' }

$ifCount = [regex]::Matches($ini, '(?m)^\s*if\s+').Count
$endifCount = [regex]::Matches($ini, '(?m)^\s*endif\s*$').Count
if ($ifCount -ne $endifCount -or $ifCount -ne 12) { throw "Generated conditional imbalance: if=$ifCount endif=$endifCount" }

$runTargets = @([regex]::Matches($ini, '(?m)^\s*run\s*=\s*([^\s;]+)') | ForEach-Object { $_.Groups[1].Value })
foreach ($target in $runTargets) {
    if ($sections -inotcontains $target) { throw "Generated INI run target has no section: $target" }
}

$resourceSections = @($sections | Where-Object { $_ -ilike 'ResourceUE4FX*' })
$resourceCopies = @([regex]::Matches($ini, '(?m)^(ResourceUE4FX[A-Za-z0-9_]+)\s*=\s*copy\s+') | ForEach-Object { $_.Groups[1].Value })
foreach ($resource in $resourceCopies) {
    if ($resourceSections -inotcontains $resource) { throw "Generated INI resource copy has no resource section: $resource" }
}

$shaderAssignments = @([regex]::Matches($ini, '(?m)^\s*(?:ps|cs)\s*=\s*([^\s;]+\.hlsl)\s*$') | ForEach-Object { $_.Groups[1].Value })
if ($shaderAssignments.Count -ne 12) { throw "Expected twelve generated shader assignments, found $($shaderAssignments.Count)." }
foreach ($shader in $shaderAssignments) {
    $path = Join-Path $modsRoot $shader
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated INI references a missing shader: $shader" }
    $record = @($manifest.files | Where-Object relativePath -eq "Mods/$shader")
    if ($record.Count -ne 1) { throw "Generated shader is absent or duplicated in the payload manifest: $shader" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$record[0].sha256) { throw "Generated shader payload hash mismatch: $shader" }
}

$overrideSections = @($sections | Where-Object { $_ -ilike 'ShaderOverrideUE4FX*' })
if ($overrideSections.Count -ne 12) { throw "Expected twelve generated shader overrides, found $($overrideSections.Count)." }
$hashes = @([regex]::Matches($ini, '(?m)^\s*hash\s*=\s*([0-9A-Fa-f]{16})\s*$') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
if ($hashes.Count -ne 12) { throw 'Every generated override must contain one 16-hex shader hash.' }
if ($hashes -contains 'e2aa1c8cb39e0a55') { throw 'Blocked downstream SSR hash leaked into the generated INI.' }
$eligibleHashes = @($manifest.controls.shaderHash | ForEach-Object { ([string]$_).ToLowerInvariant() })
foreach ($hash in @($hashes | Select-Object -Unique)) {
    if ($eligibleHashes -notcontains $hash) { throw "Generated override hash is not eligible: $hash" }
}
if ([regex]::Matches($ini, '(?m)^\s*allow_duplicate_hash\s*=\s*true\s*$').Count -ne 12) {
    throw 'Every generated override must explicitly allow its intentional duplicate hash.'
}

$generatedKeys = @([regex]::Matches($ini, '(?m)^\s*key\s*=\s*([^\r\n;]+)') | ForEach-Object { ($_.Groups[1].Value -replace '\s+', ' ').Trim().ToLowerInvariant() })
if ($generatedKeys.Count -ne 3 -or @($generatedKeys | Select-Object -Unique).Count -ne 3) { throw 'Generated keys must contain three unique bindings.' }
$liveKeyCollisions = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $LiveModsDirectory -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $LiveModsDirectory -Filter '*.ini' -File) {
        if ($file.Name -ieq 'UE4EffectsGenerated.ini') { continue }
        $text = [IO.File]::ReadAllText($file.FullName)
        foreach ($match in [regex]::Matches($text, '(?m)^\s*key\s*=\s*([^\r\n;]+)')) {
            $key = ($match.Groups[1].Value -replace '\s+', ' ').Trim().ToLowerInvariant()
            if ($generatedKeys -contains $key) {
                $liveKeyCollisions.Add([pscustomobject]@{ key = $key; file = $file.FullName })
            }
        }
    }
}
if ($liveKeyCollisions.Count) { throw "Generated key collides with an existing live binding: $($liveKeyCollisions[0].key) in $($liveKeyCollisions[0].file)" }

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    iniSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    sections = $sections.Count
    controls = @($manifest.controls).Count
    variables = $definedVariables.Count
    conditionals = $ifCount
    runTargets = $runTargets.Count
    resourceCopies = $resourceCopies.Count
    shaderAssignments = $shaderAssignments.Count
    overrides = $overrideSections.Count
    liveKeyCollisions = $liveKeyCollisions.Count
}
$reportPath = Join-Path $generatedRoot 'ini-lint-report.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 4) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

Write-Output 'UE4 generated runtime INI structural lint passed.'
[pscustomobject]@{
    Sections = $report.sections
    Controls = $report.controls
    ShaderAssignments = $report.shaderAssignments
    Overrides = $report.overrides
    LiveKeyCollisions = $report.liveKeyCollisions
    Result = 'pass'
}
