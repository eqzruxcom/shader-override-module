[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot 'Acquire-DxvkMsvcBuildPrerequisites.ps1'
$testOutput = Join-Path $root ('artifacts\_acquisition-refusal-test-' + [guid]::NewGuid().ToString('N'))

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -ne 0) {
    throw "PowerShell parse errors in $scriptPath`: $($errors.Message -join '; ')"
}

$text = [IO.File]::ReadAllText($scriptPath)
$requiredEvidence = @(
    '[switch]$AllowNetwork',
    'if (-not $AllowNetwork)',
    "'files.pythonhosted.org'",
    "'github.com'",
    "`$uri.Scheme -ne 'https'",
    'Get-FileHash -LiteralPath $partial -Algorithm SHA256',
    'Refusing downloads outside the workspace artifacts directory',
    'Refusing to overwrite an existing file with the wrong hash',
    'SystemInstalled = $false',
    'GameInstalled = $false',
    '-ExpectedGlslangArchiveSha256 $inputs.glslangValidator.archiveSha256'
)
foreach ($evidence in $requiredEvidence) {
    if ($text -notmatch [regex]::Escape($evidence)) {
        throw "Acquisition script is missing safety evidence: $evidence"
    }
}

$refused = $false
try {
    & $scriptPath -DownloadRoot $testOutput
}
catch {
    if ($_.Exception.Message -match 'Network acquisition is disabled by default') {
        $refused = $true
    }
    else {
        throw
    }
}
if (-not $refused) {
    throw 'Acquisition script did not fail closed without -AllowNetwork'
}
if (Test-Path -LiteralPath $testOutput) {
    throw 'Acquisition refusal unexpectedly wrote output'
}

Write-Host 'PASS: pinned prerequisite acquisition is explicit, HTTPS allowlisted, hash-verified, workspace-only, and fail-closed by default.'
