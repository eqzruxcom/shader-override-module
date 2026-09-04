[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$generator = Join-Path $root 'tools\New-IntergradeR3DSSGIF2EvidenceLedger.ps1'
$testRoot = Join-Path $root ('artifacts\analysis\agent2-r3d-ssgi-ledger-test\' + [Guid]::NewGuid().ToString('N'))
$first = Join-Path $testRoot 'first.json'
$second = Join-Path $testRoot 'second.json'
[IO.Directory]::CreateDirectory($testRoot) | Out-Null

try {
    & $generator -OutputPath $first | Out-Null
    & $generator -OutputPath $second | Out-Null
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $first).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $second).Hash) {
        throw 'Pending evidence ledger is not deterministic.'
    }
    $ledger = Get-Content -Raw -LiteralPath $first | ConvertFrom-Json
    $expectedGates = @(
        'live-parser-custom-hlsl','f2-off-neutral','strong-warm-bounce-still',
        'motion-disocclusion','screen-edge-subviewport','ao-ssr-invariants',
        'camera-cuts','gpu-timing','balanced-strength-promotion'
    )
    $actualGates = @($ledger.gates | ForEach-Object {[string]$_.id})
    if ($ledger.schemaVersion -ne 1 -or $ledger.result -ne 'pending-live-evidence' -or
        $ledger.packageId -ne 'agent2-r3d-ssgi-f2-standalone' -or
        $ledger.visualTarget -notmatch 'bottom reference image.*warm RGB indirect diffuse bounce.*not darker AO' -or
        $ledger.controls.F1 -ne 'reserved and unbound' -or
        $ledger.controls.F2 -ne 'standalone strong diagnostic off/on' -or
        $ledger.controls.F3 -ne 'current live unbound state preserved' -or
        $ledger.diagnostic.strength -ne 1.25 -or
        $ledger.diagnostic.classification -ne 'strong diagnostic, not balanced default' -or
        $ledger.diagnostic.nativeTemporalAO -ne 'unchanged and separate' -or
        $ledger.requiredGates -ne 9 -or $ledger.completedGates -ne 0 -or
        $ledger.installed -ne $false -or $ledger.runtimeEligible -ne $false -or
        @((Compare-Object $expectedGates $actualGates)).Count) {
        throw 'Evidence ledger does not preserve the requested visual, control, or fail-closed contract.'
    }
    foreach ($gate in @($ledger.gates)) {
        if ($gate.status -ne 'pending' -or $null -ne $gate.evidence -or $null -ne $gate.evidenceSha256 -or
            $null -ne $gate.reviewedAtUtc -or $null -ne $gate.notes -or
            @($gate.requiredEvidence).Count -lt 2 -or [string]::IsNullOrWhiteSpace([string]$gate.acceptance)) {
            throw "Gate was pre-approved or under-specified: $($gate.id)"
        }
    }
    if (@($ledger.sources).Count -ne 3) { throw 'Evidence ledger source chain is incomplete.' }
    foreach ($source in @($ledger.sources)) {
        $path = Join-Path $root ([string]$source.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$source.sha256) {
            throw "Evidence ledger source hash is invalid: $($source.path)"
        }
    }
    if (@($ledger.captureRules | Where-Object {$_ -match 'Parser success cannot satisfy visual or performance gates'}).Count -ne 1) {
        throw 'Evidence ledger permits parser evidence to substitute for visual/performance evidence.'
    }
    [pscustomobject]@{
        Result = 'pass'
        Deterministic = $true
        RequiredGates = $ledger.requiredGates
        CompletedGates = $ledger.completedGates
        StrongNotBalanced = $true
        NativeAOSeparate = $true
        Installed = $false
        RuntimeEligible = $false
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        [IO.Directory]::Delete([IO.Path]::GetFullPath($testRoot),$true)
    }
}
