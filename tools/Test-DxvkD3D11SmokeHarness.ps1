[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$patchedRuntimeTest = Join-Path $PSScriptRoot 'Test-DxvkD3D11PatchedRuntime.ps1'
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($patchedRuntimeTest, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -ne 0) {
    throw "PowerShell parse errors in patched-runtime smoke test: $($errors.Message -join '; ')"
}
$patchedRuntimeText = [IO.File]::ReadAllText($patchedRuntimeTest)
foreach ($evidence in @(
    '$caseLogRoot = Join-Path $logRoot $Name',
    '$env:DXVK_LOG_PATH = $caseLogRoot',
    'D3D11: Loaded shader replacement $identity from',
    'D3D11: Rejecting shader replacement ${identity}:',
    'LogSha256 = (Get-FileHash -Algorithm SHA256',
    'CaseEvidence = $caseEvidence',
    'Installed = $false'
)) {
    if ($patchedRuntimeText -notmatch [regex]::Escape($evidence)) {
        throw "Patched-runtime smoke test is missing log-evidence contract: $evidence"
    }
}

$build = & (Join-Path $PSScriptRoot 'Build-DxvkD3D11SmokeHarness.ps1')
& $build.Executable $build.OriginalBytecode 7
if ($LASTEXITCODE -ne 0) {
    throw "Native D3D11 smoke baseline failed (exit code $LASTEXITCODE)"
}

$manifest = Get-Content -LiteralPath $build.ManifestPath -Raw | ConvertFrom-Json
if ($manifest.Identity -ne $build.Identity -or -not $manifest.CompatibilityVerified) {
    throw 'Smoke manifest identity or compatibility proof is inconsistent'
}
if ($manifest.Installed -or $manifest.RuntimeEligible) {
    throw 'Smoke harness artifact must remain non-installed and non-runtime-eligible'
}

Write-Host 'PASS: native D3D11 executed the original compute shader (7); the compatible canonical replacement (42) is staged for patched-DXVK validation.'
