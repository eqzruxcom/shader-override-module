[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ao-temporal-power-isolation-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$generator = Join-Path $repoRoot 'tools\New-IntergradeTemporalAOCandidate.ps1'
$nativePath = Join-Path $repoRoot 'artifacts\captured-shaders\a77b589dce5822d6-ps\a77b589dce5822d6-ps_decompiled.txt'
$nativeAssemblyPath = Join-Path $repoRoot 'artifacts\captured-shaders\a77b589dce5822d6-ps\a77b589dce5822d6-ps_dumpbin.asm'
$kernelPath = Join-Path $repoRoot 'src\Effects\AO\RemakeTemporalAOPower.hlsl'
$runRoot = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
$positiveRoot = Join-Path $runRoot 'positive'
$negativeRoot = Join-Path $runRoot 'negative'
New-Item -ItemType Directory -Path $positiveRoot,$negativeRoot -Force | Out-Null

function Normalize-Newlines([string]$Text) {
    $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-InterfaceDeclarations([string]$AssemblyPath) {
    @(
        Get-Content -LiteralPath $AssemblyPath |
            Where-Object { $_ -match '^dcl_' -and $_ -notmatch '^dcl_temps\s' } |
            ForEach-Object { $_.Trim() } |
            Sort-Object
    )
}

function Assert-CompiledPowerSequence([string]$CandidateAssemblyPath, [double]$Power) {
    $nativeAssembly = Normalize-Newlines ([IO.File]::ReadAllText($nativeAssemblyPath))
    $candidateAssembly = Normalize-Newlines ([IO.File]::ReadAllText($CandidateAssemblyPath))
    $nativeLogCount = [regex]::Matches($nativeAssembly, '(?m)^log\s').Count
    $nativeExpCount = [regex]::Matches($nativeAssembly, '(?m)^exp\s').Count
    if ([regex]::Matches($candidateAssembly, '(?m)^log\s').Count -ne ($nativeLogCount + 1) -or
        [regex]::Matches($candidateAssembly, '(?m)^exp\s').Count -ne ($nativeExpCount + 1)) {
        throw "Candidate does not contain exactly one added compiled power pair: $CandidateAssemblyPath"
    }

    $literal = $Power.ToString('0.000000', [Globalization.CultureInfo]::InvariantCulture)
    $sequence = "(?m)^log (?<powerRegister>r\d+\.[xyzw]), \k<powerRegister>`n" +
        "mul \k<powerRegister>, \k<powerRegister>, l\($([regex]::Escape($literal))\)`n" +
        "exp r\d+\.[xyzw], \k<powerRegister>$"
    $powerMatch = [regex]::Match($candidateAssembly, $sequence)
    if (-not $powerMatch.Success) { throw "Compiled AO power sequence or literal is missing: $CandidateAssemblyPath" }
    $historyIndex = $candidateAssembly.IndexOf('sample_l_indexable(texture2d)(float,float,float,float)', $powerMatch.Index, [StringComparison]::Ordinal)
    if ($historyIndex -lt 0 -or $candidateAssembly.IndexOf('t3.xyzw', $historyIndex, [StringComparison]::Ordinal) -lt 0) {
        throw "Compiled AO power sequence is not followed by the native t3 history sample: $CandidateAssemblyPath"
    }
}

function Assert-PowerCurve([double]$Power, [double]$StrongerPower) {
    $previous = -1.0
    foreach ($visibility in @(0.0, 0.05, 0.25, 0.5, 0.75, 1.0)) {
        $value = [Math]::Pow($visibility, $Power)
        $strongerValue = [Math]::Pow($visibility, $StrongerPower)
        if ($value -lt $previous) { throw 'AO visibility power curve is not monotonic.' }
        if ($visibility -gt 0.0 -and $visibility -lt 1.0 -and $value -ge $visibility) {
            throw 'AO visibility power curve does not strengthen sub-neutral occlusion.'
        }
        if ($visibility -gt 0.0 -and $visibility -lt 1.0 -and $strongerValue -ge $value) {
            throw 'The Strong AO preset is not stronger than Balanced.'
        }
        $previous = $value
    }
    if ([Math]::Pow(0.0, $Power) -ne 0.0 -or [Math]::Pow(1.0, $Power) -ne 1.0) {
        throw 'AO visibility power curve does not preserve neutral endpoints.'
    }
}

function Assert-SurgicalTransform([string]$CandidatePath, [double]$Power) {
    $native = Normalize-Newlines ([IO.File]::ReadAllText($nativePath))
    $candidate = Normalize-Newlines ([IO.File]::ReadAllText($CandidatePath))
    $kernel = (Normalize-Newlines ([IO.File]::ReadAllText($kernelPath))).TrimEnd()
    $kernelBlock = $kernel + "`n`n"
    $kernelIndex = $candidate.IndexOf($kernelBlock, [StringComparison]::Ordinal)
    if ($kernelIndex -lt 0 -or $candidate.IndexOf($kernelBlock, $kernelIndex + 1, [StringComparison]::Ordinal) -ge 0) {
        throw "Candidate does not contain exactly one pinned AO kernel: $CandidatePath"
    }
    if ($candidate.IndexOf('void main(', [StringComparison]::Ordinal) -ne ($kernelIndex + $kernelBlock.Length)) {
        throw "Candidate AO kernel is not immediately before main: $CandidatePath"
    }

    $withoutKernel = $candidate.Remove($kernelIndex, $kernelBlock.Length)
    $powerLiteral = $Power.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $powerLine = "  r2.w = RemakeTemporalAOApplyCurrentPower(r2.w, $powerLiteral);`n"
    if ([regex]::Matches($withoutKernel, [regex]::Escape($powerLine)).Count -ne 1) {
        throw "Candidate does not contain exactly one expected AO power insertion: $CandidatePath"
    }
    if (-not $withoutKernel.Replace($powerLine, '').Equals($native, [StringComparison]::Ordinal)) {
        throw "Candidate changed native shader text outside the intended AO insertion: $CandidatePath"
    }
    if ([regex]::Matches($candidate, '(?m)^  o0\.xyzw = r2\.wxyz;$').Count -ne 1) {
        throw "Candidate did not preserve the native packed output: $CandidatePath"
    }
    if ($candidate -match '(?i)VK_F1|VK_F2|VK_F3|\[Key|Key\w*\s*=') {
        throw "Candidate source unexpectedly emits runtime controls: $CandidatePath"
    }
}

$nativeInterface = Get-InterfaceDeclarations $nativeAssemblyPath
Assert-PowerCurve -Power 1.25 -StrongerPower 1.50

$balanced = & $generator -Preset Balanced -OutputDirectory $positiveRoot
$strong = & $generator -Preset Strong -OutputDirectory $positiveRoot
Assert-SurgicalTransform -CandidatePath $balanced.Source -Power 1.25
Assert-SurgicalTransform -CandidatePath $strong.Source -Power 1.50
Assert-CompiledPowerSequence -CandidateAssemblyPath $balanced.Assembly -Power 1.25
Assert-CompiledPowerSequence -CandidateAssemblyPath $strong.Assembly -Power 1.50

foreach ($candidate in @($balanced,$strong)) {
    $manifest = Get-Content -Raw -LiteralPath $candidate.Manifest | ConvertFrom-Json
    if ($manifest.runtimeEligible -ne $false -or $manifest.hotkeysEmitted -ne $false) {
        throw "Candidate escaped the offline-only gate: $($candidate.Preset)"
    }
    if (($manifest.reservedFutureControls -join ',') -ne 'F1,F2,F3') {
        throw "Future AO control reservation drifted: $($candidate.Preset)"
    }
    if ($manifest.futureControlPlan.F1 -ne 'Original/native AO' -or
        $manifest.futureControlPlan.F2 -ne 'Balanced power 1.25' -or
        $manifest.futureControlPlan.F3 -ne 'Strong power 1.50') {
        throw "Future AO control roles drifted: $($candidate.Preset)"
    }
    if ($manifest.futureControlOwnership.F1 -ne 'AO Original' -or $manifest.futureControlOwnership.F2 -ne 'AO Balanced' -or $manifest.futureControlOwnership.F3 -ne 'AO Strong') {
        throw "Future control ownership drifted: $($candidate.Preset)"
    }
    $candidateInterface = Get-InterfaceDeclarations $candidate.Assembly
    if (($candidateInterface -join "`n") -cne ($nativeInterface -join "`n")) {
        throw "Compiled shader interface drifted from native: $($candidate.Preset)"
    }
}

$nativeText = [IO.File]::ReadAllText($nativePath)
$mutatedText = $nativeText.Replace('r2.w = max(0, r2.x);', 'r2.w = max(0.0, r2.x);')
if ($mutatedText -eq $nativeText) { throw 'Negative fixture could not mutate the native AO anchor.' }
$mutatedPath = Join-Path $negativeRoot 'a77b-mutated-source.hlsl'
[IO.File]::WriteAllText($mutatedPath, $mutatedText, [Text.UTF8Encoding]::new($false))

$rejected = $false
try {
    & $generator -Preset Balanced -SourcePath $mutatedPath -OutputDirectory (Join-Path $negativeRoot 'rejected-output') | Out-Null
} catch {
    if ($_.Exception.Message -notmatch 'Refusing stale or changed SSAO source') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'Generator accepted a stale or changed temporal-AO source.' }
$rejectedOutput = Join-Path $negativeRoot 'rejected-output'
if (Test-Path -LiteralPath $rejectedOutput) {
    if (@(Get-ChildItem -LiteralPath $rejectedOutput -File -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'Rejected stale source emitted candidate artifacts.'
    }
}

$report = [ordered]@{
    schemaVersion = 1
    result = 'pass'
    shaderHash = 'a77b589dce5822d6'
    surgicalSourceTransform = $true
    numericalCurveContract = 'monotonic; endpoints preserved; Strong darker than Balanced for 0 < visibility < 1'
    compiledInterfaceMatchesNative = $true
    compiledPowerSequenceBeforeHistorySample = $true
    staleSourceRejectedBeforeArtifactEmission = $true
    nativePackedOutputPreserved = 'o0.xyzw = r2.wxyz'
    runtimeEligible = $false
    hotkeysEmitted = $false
    reservedFutureControls = @('F1','F2','F3')
    futureControlPlan = [ordered]@{
        F1 = 'Original/native AO'
        F2 = 'Balanced power 1.25'
        F3 = 'Strong power 1.50'
    }
    futureControlOwnership = [ordered]@{ F1='AO Original'; F2='AO Balanced'; F3='AO Strong' }
}
$reportPath = Join-Path $runRoot 'report.json'
[IO.File]::WriteAllText($reportPath, (($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output 'Intergrade temporal-AO isolation tests passed.'
Write-Output "Report: $reportPath"
