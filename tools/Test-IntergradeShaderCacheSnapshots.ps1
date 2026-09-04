[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('intergrade-shader-snapshot-' + [guid]::NewGuid().ToString('N'))
$cache = Join-Path $fixture 'ShaderCache'
$before = Join-Path $fixture 'before.json'
$after = Join-Path $fixture 'after.json'
$afterAgain = Join-Path $fixture 'after-again.json'
$delta = Join-Path $fixture 'delta.json'

try {
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $cache '1111111111111111-vs.bin'), [byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $cache '2222222222222222-ps.bin'), [byte[]](4,5,6))
    & (Join-Path $PSScriptRoot 'New-IntergradeShaderCacheSnapshot.ps1') -ShaderCacheDirectory $cache -SnapshotId before -OutputPath $before | Out-Null

    [IO.File]::WriteAllBytes((Join-Path $cache '2222222222222222-ps.bin'), [byte[]](4,5,6,7))
    [IO.File]::WriteAllBytes((Join-Path $cache '3333333333333333-cs.bin'), [byte[]](8,9))
    [IO.File]::WriteAllBytes((Join-Path $cache '3333333333333333-cs_replace.bin'), [byte[]](99))
    & (Join-Path $PSScriptRoot 'New-IntergradeShaderCacheSnapshot.ps1') -ShaderCacheDirectory $cache -SnapshotId after -OutputPath $after | Out-Null
    & (Join-Path $PSScriptRoot 'New-IntergradeShaderCacheSnapshot.ps1') -ShaderCacheDirectory $cache -SnapshotId after -OutputPath $afterAgain | Out-Null

    if ((Get-FileHash -LiteralPath $after -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $afterAgain -Algorithm SHA256).Hash) {
        throw 'Equivalent ShaderCache snapshots are not byte-deterministic.'
    }

    & (Join-Path $PSScriptRoot 'Compare-IntergradeShaderCacheSnapshots.ps1') -BeforePath $before -AfterPath $after -OutputPath $delta | Out-Null
    $report = Get-Content -Raw -LiteralPath $delta | ConvertFrom-Json
    if ($report.counts.added -ne 1 -or $report.counts.removed -ne 0 -or $report.counts.changed -ne 1) {
        throw 'Unexpected regional ShaderCache delta counts.'
    }
    if (@($report.added) -ne '3333333333333333-cs' -or $report.addedByStage.cs -ne 1) {
        throw 'Added compute shader was not classified correctly.'
    }
    if (@($report.changed).Count -ne 1 -or $report.changed[0].identity -ne '2222222222222222-ps') {
        throw 'Changed pixel shader was not reported correctly.'
    }
    if ((Get-Content -Raw -LiteralPath $after) -match [regex]::Escape($fixture)) {
        throw 'Snapshot leaked an absolute machine path.'
    }

    Write-Host 'PASS: deterministic ShaderCache snapshots isolate added regional shaders, reject replacement artifacts, and report unexpected binary drift.'
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
