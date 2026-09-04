[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifacts = Join-Path $workspace 'artifacts'
$fixtureRoot = Join-Path $artifacts ('test-fnv-neural-input-' + [Guid]::NewGuid().ToString('N'))
$importPath = Join-Path $PSScriptRoot 'Import-FalloutNewVegasDlss5NeuralInputSet.ps1'
$inputAssertPath = Join-Path $PSScriptRoot 'Assert-FalloutNewVegasDlss5NeuralInputs.ps1'

try {
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'source')) | Out-Null
    $signedMicrosoftPe = Join-Path $env:WINDIR 'System32\kernel32.dll'
    $reno = Join-Path $fixtureRoot 'source\renodx-dlss5-fixture.addon64'
    $dlss = Join-Path $fixtureRoot 'source\nvngx_dlss.dll'
    $nr = Join-Path $fixtureRoot 'source\nvngx_dlssnr.dll'
    Copy-Item -LiteralPath $signedMicrosoftPe -Destination $reno
    Copy-Item -LiteralPath $signedMicrosoftPe -Destination $dlss
    Copy-Item -LiteralPath $signedMicrosoftPe -Destination $nr
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $signedMicrosoftPe).Hash.ToUpperInvariant()
    $output = Join-Path $fixtureRoot 'output'
    $rejected = $false
    try {
        $null = & $inputAssertPath -RenoDxAddonPath $reno -NvngxDlssPath $dlss -NvngxDlssNrPath $nr `
            -ExpectedRenoDxSha256 $hash -ExpectedDlssSha256 $hash -ExpectedDlssNrSha256 $hash
    }
    catch { $rejected = $_.Exception.Message -match 'not signed by NVIDIA Corporation' }
    if (-not $rejected) { throw 'Neural-input authenticity validator accepted a non-NVIDIA signer.' }
    $rejected = $false
    try {
        $null = & $importPath -RenoDxAddonPath $reno -NvngxDlssPath $dlss -NvngxDlssNrPath $nr `
            -InputSetId 'must-reject-microsoft-signer' -ExpectedRenoDxSha256 $hash -ExpectedDlssSha256 $hash `
            -ExpectedDlssNrSha256 $hash -OutputParent $output
    }
    catch { $rejected = $_.Exception.Message -match 'do not match the reviewed' }
    if (-not $rejected) { throw 'Neural-input importer accepted an unreviewed hash profile.' }
    if (Test-Path -LiteralPath (Join-Path $output 'must-reject-microsoft-signer')) { throw 'Rejected neural-input import left a final set behind.' }
    Write-Host 'PASS: New Vegas neural-input intake rejects non-NVIDIA signers and unreviewed hash profiles without leaving output.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
