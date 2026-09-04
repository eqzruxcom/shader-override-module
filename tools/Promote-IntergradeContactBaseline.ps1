[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64',
    [string]$PreDiagnosticRollback,
    [string]$OutputDirectory,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($PreDiagnosticRollback)) {
    $PreDiagnosticRollback = Join-Path $repo 'artifacts\live-rollbacks\cloud-clothing-route-20260901-044544-967'
}
$pre = (Resolve-Path -LiteralPath $PreDiagnosticRollback).Path.TrimEnd('\')
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repo "artifacts\contact-baseline-promotions\$stamp"
}
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts\contact-baseline-promotions')).TrimEnd('\')
if (-not $output.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must remain below artifacts/contact-baseline-promotions.' }
if (Test-Path -LiteralPath $output) { throw 'Output already exists; preserve earlier evidence.' }

$liveShader = Join-Path $runtime 'ShaderFixes\62b33a2d1e505241-cs.txt'
$liveIni = Join-Path $runtime 'Mods\ContactShadows.ini'
$baselineShader = Get-ChildItem -LiteralPath $pre -Recurse -File | Where-Object Name -eq '62b33a2d1e505241-cs.txt' | Select-Object -First 1
$headerSource = Join-Path $repo 'working-code\Contact shadows - Rebirth Mod - Code worked\original-remake\62b33a2d1e505241-cs.asm'
foreach ($path in @($liveShader,$liveIni,$headerSource)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" } }
if ($null -eq $baselineShader) { throw 'Pre-diagnostic rollback does not contain the 62b shader.' }

$utf8 = [Text.UTF8Encoding]::new($false)
function Instructions([string[]]$Lines) {
    return (($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('//') }) -join "`n")
}

$liveText = Get-Content -LiteralPath $liveShader -Raw
if ($liveText -notmatch 'Page Up diagnostic: make only material-ID 1 unoccluded') { throw 'The expected temporary Page Up diagnostic is not active.' }
if ($liveText -notmatch 'l\(28,\s*0,\s*0,\s*0\),\s*t120\.xyzw') { throw 'The expected shader-side Page Up load is missing.' }

$baselineLines = @(Get-Content -LiteralPath $baselineShader.FullName)
$baselineProfile = [array]::IndexOf($baselineLines,'cs_5_0')
if ($baselineProfile -lt 0) { throw 'Pre-diagnostic shader lacks cs_5_0.' }
$baselineBody = @($baselineLines[$baselineProfile..($baselineLines.Count-1)])
if ((Instructions $baselineBody) -match 'l\(28,\s*0,\s*0,\s*0\),\s*t120\.xyzw') { throw 'Pre-diagnostic shader unexpectedly contains Page Up.' }
if ((Instructions $baselineBody) -notmatch 'l\(31,\s*0,\s*0,\s*0\),\s*t120\.xyzw') { throw 'Pre-diagnostic shader lacks the Page Down master.' }

$headerLines = @(Get-Content -LiteralPath $headerSource)
$headerProfile = [array]::IndexOf($headerLines,'cs_5_0')
if ($headerProfile -lt 1) { throw 'Authoritative shader header is unavailable.' }
$header = @($headerLines[0..($headerProfile-1)])
$promotedShaderLines = @($header + '//Frustum Fix' + $baselineBody)
if ((Instructions $promotedShaderLines) -cne (Instructions $baselineBody)) { throw 'Promotion changed pre-diagnostic shader instructions.' }

$ini = Get-Content -LiteralPath $liveIni -Raw
if ($ini -notmatch '(?m)^global \$ue4fx_master_injected_v1 = 1\s*$') { throw 'Page Down master is not the current live variable.' }
if ($ini -notmatch '(?m)^global \$ue4fx_material1_contact_route_v1 = 0\s*$') { throw 'Temporary Page Up variable is not present.' }
$promotedIni = [regex]::Replace($ini,'(?m)^global \$ue4fx_material1_contact_route_v1 = 0\s*\r?\n','')
$promotedIni = [regex]::Replace($promotedIni,'(?ms)^\[KeyUE4FXMaterial1RoutePageUp\]\s*\r?\n.*?(?=^\[|\z)','')
$promotedIni = [regex]::Replace($promotedIni,'(?m)^x28 = \$ue4fx_material1_contact_route_v1\s*\r?\n','')
$promotedIni = $promotedIni.Replace('; Page Down is the master injected-code switch. Page Up is the active experiment.','; Page Down is the sole retained-code master. Page Up is free for the next experiment.')
$promotedIni = [regex]::Replace($promotedIni,'(?m)^; Page Up ON.*\r?\n','')
$promotedIni = [regex]::Replace($promotedIni,'(?m)^; It does NOT.*\r?\n','')
$promotedIni = [regex]::Replace($promotedIni,'(?m)^; Material ID 1.*\r?\n','')
if ($promotedIni -match '(?i)material1_contact|VK_PRIOR|^x28\s*=|Page Up ON|material-ID 1') { throw 'Temporary Page Up INI state survived promotion.' }
if (([regex]::Matches($promotedIni,'(?m)^x31 = \$ue4fx_master_injected_v1\s*$')).Count -ne 5) { throw 'Page Down is not bound to all five retained shaders.' }

$stageFixes = Join-Path $output 'ShaderFixes'
$stageMods = Join-Path $output 'Mods'
[IO.Directory]::CreateDirectory($stageFixes) | Out-Null
[IO.Directory]::CreateDirectory($stageMods) | Out-Null
$stagedShader = Join-Path $stageFixes '62b33a2d1e505241-cs.txt'
$stagedIni = Join-Path $stageMods 'ContactShadows.ini'
[IO.File]::WriteAllText($stagedShader,(($promotedShaderLines -join "`n")+"`n"),$utf8)
[IO.File]::WriteAllText($stagedIni,($promotedIni.TrimEnd()+"`n"),$utf8)

$rollback = $null
if ($Install) {
    $rollback = Join-Path $repo "artifacts\live-rollbacks\contact-baseline-promotion-$stamp"
    [IO.Directory]::CreateDirectory((Join-Path $rollback 'ShaderFixes')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $rollback 'Mods')) | Out-Null
    Copy-Item -LiteralPath $liveShader -Destination (Join-Path $rollback 'ShaderFixes\62b33a2d1e505241-cs.txt')
    Copy-Item -LiteralPath $liveIni -Destination (Join-Path $rollback 'Mods\ContactShadows.ini')
    Copy-Item -LiteralPath $stagedShader -Destination $liveShader -Force
    Copy-Item -LiteralPath $stagedIni -Destination $liveIni -Force
}

$manifest = [ordered]@{
    schemaVersion=1;generatedAtUtc=[DateTime]::UtcNow.ToString('o')
    result=$(if($Install){'installed'}else{'staged'})
    action='Promoted confirmed contact-shadow baseline; removed temporary material-ID1 Page Up route from shader and INI.'
    retained=@('Page Down master on all five shaders','//Frustum Fix on 62b','authoritative original signature header','accepted 62b contact/frustum instructions')
    removed=@('Page Up key section','material-route variable','62b x28 binding','62b material-ID1 shader branch')
    shaderInstructionSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes((Instructions $promotedShaderLines))))
    stagedShaderSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $stagedShader).Hash
    stagedIniSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $stagedIni).Hash
    installed=[bool]$Install;rollbackDirectory=$rollback;reloadRequired=[bool]$Install
}
$manifestPath=Join-Path $output 'manifest.json'
[IO.File]::WriteAllText($manifestPath,(($manifest|ConvertTo-Json -Depth 8)+"`n"),$utf8)
[pscustomobject]@{Result=$manifest.result;PageDownShaders=5;PageUpShaders=0;Rollback=$rollback;Manifest=$manifestPath;Sha256=(Get-FileHash -LiteralPath $manifestPath).Hash}
