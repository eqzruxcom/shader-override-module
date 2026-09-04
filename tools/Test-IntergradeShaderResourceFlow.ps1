[CmdletBinding()]
param(
    [string]$CaptureDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\FrameAnalysis-2026-09-04-001641'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$analyzer = Join-Path $PSScriptRoot 'Analyze-IntergradeShaderResourceFlow.ps1'
$outRoot = Join-Path $root ('artifacts\resource-flow-tests\' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($outRoot)
try {
    $c473Path = Join-Path $outRoot 'c473.json'
    & $analyzer -CaptureDirectory $CaptureDirectory -ShaderHash c473ab75b7519f7e -Stage ps -OutputPath $c473Path | Out-Null
    $c473 = Get-Content -Raw -LiteralPath $c473Path | ConvertFrom-Json
    if (-not [bool]$c473.target.observed -or [int]$c473.target.executionCount -ne 1) { throw 'Known c473 target was not observed exactly once.' }
    $c473Outputs = @($c473.executions[0].outputs)
    if ($c473Outputs.Count -ne 1) { throw "Expected one c473 render target; found $($c473Outputs.Count)." }
    $c473First = $c473Outputs[0].firstConsumer
    if ($null -eq $c473First -or $c473First.shader -ne 'af6cd28a0108a18a' -or $c473First.stage -ne 'ps' -or @($c473First.inputSlots) -notcontains 0) {
        throw 'c473 output did not flow first into af6 t0 as captured.'
    }

    $a26Path = Join-Path $outRoot 'a26.json'
    & $analyzer -CaptureDirectory $CaptureDirectory -ShaderHash a26b3473289dba2d -Stage cs -OutputPath $a26Path | Out-Null
    $a26 = Get-Content -Raw -LiteralPath $a26Path | ConvertFrom-Json
    if (-not [bool]$a26.target.observed -or [int]$a26.target.executionCount -ne 1) { throw 'Known a26 target was not observed exactly once.' }
    $out1 = @($a26.executions[0].outputs | Where-Object slot -eq 1)
    if ($out1.Count -ne 1) { throw 'Known a26 tile output u1 is missing.' }
    $a26First = $out1[0].firstConsumer
    if ($null -eq $a26First -or $a26First.shader -ne '58101bdcc044cd88' -or $a26First.stage -ne 'cs' -or @($a26First.inputSlots) -notcontains 0) {
        throw 'a26 u1 did not flow first into 581 t0 as captured.'
    }

    $absentPath = Join-Path $outRoot 'adb-absent.json'
    & $analyzer -CaptureDirectory $CaptureDirectory -ShaderHash adb544f9a11d6c7e -Stage cs -OutputPath $absentPath | Out-Null
    $absent = Get-Content -Raw -LiteralPath $absentPath | ConvertFrom-Json
    if ([bool]$absent.target.observed -or [int]$absent.target.executionCount -ne 0) { throw 'adb should remain scene-specifically absent in this retained capture.' }

    [pscustomobject]@{
        Result='pass'
        C473FirstConsumer='af6cd28a0108a18a-ps:t0'
        A26U1FirstConsumer='58101bdcc044cd88-cs:t0'
        AbsentControl='adb544f9a11d6c7e-cs'
    }
}
finally {
    if (Test-Path -LiteralPath $outRoot) { Remove-Item -LiteralPath $outRoot -Recurse -Force }
}

