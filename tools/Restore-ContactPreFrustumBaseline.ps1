[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$previous = Get-Content -LiteralPath (Join-Path $repo 'artifacts/contact-edge-three-presets-20260831-v1/receipt.json') -Raw | ConvertFrom-Json
$originalRoot = Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeRebirthContact-experiment-live-v1'
$original = Get-Content -LiteralPath (Join-Path $originalRoot 'install-receipt.json') -Raw | ConvertFrom-Json
$live = [IO.Path]::GetFullPath($previous.liveRoot).TrimEnd('\')
if ($live -ne 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64') { throw 'Unexpected game root' }
$saved = Join-Path $repo 'working-code/Frustum Fix/20260831-v1'
$restore = Join-Path $repo 'artifacts/contact-pre-frustum-restored-20260831-v1'
foreach ($path in @($saved,$restore)) { if (Test-Path -LiteralPath $path) { throw "Preserve existing package: $path" } }
function Assert-Hash([string]$path,[string]$expected) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw "Changed file: $path" }
}
function Copy-Checked([string]$source,[string]$target) {
    $sha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    Copy-Item -LiteralPath $source -Destination $target
    Assert-Hash $target $sha
}
function Patch-Text([string]$path,[string]$new) {
    $old = [IO.File]::ReadAllText($path).Replace("`r`n","`n").TrimEnd("`n")
    $new = $new.Replace("`r`n","`n").TrimEnd("`n")
    $patch = "*** Begin Patch`n*** Update File: $($path.Replace('\','/'))`n@@`n"
    $patch += (($old -split "`n" | ForEach-Object { '-' + $_ }) -join "`n") + "`n"
    $patch += (($new -split "`n" | ForEach-Object { '+' + $_ }) -join "`n") + "`n*** End Patch`n"
    & 'C:/Users/EQZITARA/AppData/Local/OpenAI/Codex/bin/b99306303521e97e/codex.exe' --codex-run-as-apply-patch $patch
    if ($LASTEXITCODE -ne 0) { throw "Patch failed: $path" }
}
function Disable-KeyBlocks([string]$text) {
    return [regex]::Replace($text, '(?ms)^\[Key[^\r\n]*\].*?(?=^\[|\z)', {
        param($match)
        (($match.Value.TrimEnd("`r","`n") -split '\r?\n' | ForEach-Object { '; ' + $_ }) -join "`n") + "`n`n"
    })
}
$allowed = @('ShaderFixes/c30cdc8365df9840-cs.txt','ShaderFixes/62b33a2d1e505241-cs.txt','ShaderFixes/5a9fbefe0ab6f815-cs.txt','ShaderFixes/0e97888f9a8767da-cs.txt','ShaderFixes/08bb8764f1840179-cs.txt','Mods/ContactShadows.ini')
if (@(Compare-Object ($allowed | Sort-Object) ($original.files.relativePath | Sort-Object)).Count) { throw 'Unexpected original payload' }
Assert-Hash (Join-Path $live 'Mods/ContactShadows.ini') $previous.installedSha256
foreach ($entry in $previous.protectedFiles) { Assert-Hash (Join-Path $live $entry.path) $entry.sha256 }
foreach ($entry in $original.files) { Assert-Hash (Join-Path $originalRoot $entry.relativePath) $entry.installedSha256 }
Assert-Hash $original.executable.path $original.executable.sha256
foreach ($relative in $allowed) {
    Copy-Checked (Join-Path $live $relative) (Join-Path $saved "pre-revert/$relative")
    Copy-Checked (Join-Path $live $relative) (Join-Path $saved "accepted-runtime/$relative")
    Copy-Checked (Join-Path $originalRoot $relative) (Join-Path $restore "payload/$relative")
}
$acceptedIni = Join-Path $saved 'accepted-runtime/Mods/ContactShadows.ini'
$accepted = Disable-KeyBlocks ([IO.File]::ReadAllText($acceptedIni))
$accepted = $accepted.Replace('; Starts with working donor contact shadows ON and fade 0%.','; Accepted preset 2: contacts ON, opacity 0 at LEFT edge, full strength at 6%.')
$accepted = $accepted.Replace('global $ue4fx_contact_edge_width_v2 = 0', 'global $ue4fx_contact_edge_width_v2 = 0.06')
Patch-Text $acceptedIni ("; //Frustum Fix`n; PARKED: not installed. Old contact hotkey blocks below are disabled.`n" + $accepted)
$source = Join-Path $repo 'artifacts/contact-edge-profile-development-20260831-v1/src/Effects/Lighting/ContactEdgeFade.hlsl'
$savedSource = Join-Path $saved 'source/ContactEdgeFade.hlsl'
Copy-Checked $source $savedSource
Patch-Text $savedSource ("//Frustum Fix`n" + [IO.File]::ReadAllText($savedSource))
$restoreIni = Join-Path $restore 'payload/Mods/ContactShadows.ini'
$restored = Disable-KeyBlocks ([IO.File]::ReadAllText($restoreIni))
$restored = $restored.Replace('global $ue4fx_rebirth_contact_experiment_v1 = 0','global $ue4fx_rebirth_contact_experiment_v1 = 1')
Patch-Text $restoreIni ("; Pre-frustum contact baseline restored for shader-family coverage investigation.`n; Contacts ON. Old contact hotkeys commented out. F9/F10 are untouched.`n" + $restored)
foreach ($path in @($acceptedIni,$restoreIni)) {
    if ([IO.File]::ReadAllText($path) -match '(?im)^\s*(?:\[Key|key\s*=)') { throw 'Contact hotkey remains active' }
}
if ([IO.File]::ReadAllText($restoreIni) -match '(?im)^\s*[xy]29\s*=') { throw 'Fade parameters remained in restored INI' }
$oldOverrides = ([IO.File]::ReadAllText((Join-Path $originalRoot 'Mods/ContactShadows.ini')) -split '(?m)(?=^\[ShaderOverride)',2)[1]
$newOverrides = ([IO.File]::ReadAllText($restoreIni) -split '(?m)(?=^\[ShaderOverride)',2)[1]
if ($oldOverrides.Replace("`r`n","`n").Trim() -cne $newOverrides.Replace("`r`n","`n").Trim()) { throw 'Original shader bindings changed' }
$protected = @($previous.protectedFiles | Where-Object { $_.path -notin $allowed })
# Recheck all targets after staging and before any live copy.
Assert-Hash (Join-Path $live 'Mods/ContactShadows.ini') $previous.installedSha256
foreach ($entry in $previous.protectedFiles) { Assert-Hash (Join-Path $live $entry.path) $entry.sha256 }
$logOffset = (Get-Item -LiteralPath $previous.logPath).Length
$installed = @()
foreach ($relative in $allowed) {
    Copy-Checked (Join-Path $restore "payload/$relative") (Join-Path $live $relative)
    $installed += [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $live $relative)).Hash}
}
foreach ($entry in $protected) { Assert-Hash (Join-Path $live $entry.path) $entry.sha256 }
foreach ($entry in $original.files | Where-Object relativePath -like 'ShaderFixes/*') { Assert-Hash (Join-Path $live $entry.relativePath) $entry.installedSha256 }
$record = [ordered]@{
    state='installed-awaiting-F10'; createdAtUtc=[datetime]::UtcNow.ToString('o'); liveRoot=$live
    label='//Frustum Fix'; parkedFix=$saved; userAcceptedPreset=2; cutoffPercent=0; fullStrengthPercent=6
    userAssessment='2 is good; then requested pre-fade baseline to investigate incomplete and dynamic/non-dynamic coverage'
    issueScope='Unconfirmed; do not assume static-only or all shader families'
    preFadeShaderFilesExact=5; defaultContactsEnabled=$true; activeContactHotkeys=0
    originalPackage=$originalRoot; installedFiles=$installed; protectedFiles=$protected
    rollbackFolder=(Join-Path $saved 'pre-revert'); logPath=$previous.logPath; logByteOffset=$logOffset
    headerRestorationPending=$true; nativeTemporalHistoryInstalled=$false; releaseEligible=$false
}
[IO.File]::WriteAllText((Join-Path $restore 'receipt.json'),($record | ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
$inventory = @(Get-ChildItem -LiteralPath $saved -File -Recurse | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($saved.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
[IO.File]::WriteAllText((Join-Path $saved 'manifest.json'),([ordered]@{label='//Frustum Fix';state='parked-not-installed';acceptedPreset=2;opacityRamp='left 0% to 6%';originalSource=$source;sourceHeaderOnlyChange=$true;runtimeShaderMathUnchanged=$true;files=$inventory} | ConvertTo-Json -Depth 6)+"`n",[Text.UTF8Encoding]::new($false))
$record | ConvertTo-Json -Depth 8
