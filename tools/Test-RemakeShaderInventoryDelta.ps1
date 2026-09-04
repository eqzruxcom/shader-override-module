[CmdletBinding()]
param(
    [string]$InventoryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\rebirth-v2.2.1-remake-area-inventory.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$comparer = Join-Path $PSScriptRoot 'Compare-RemakeShaderInventories.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('remake-shader-delta-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)
try {
    $sameOutput = Join-Path $temporaryRoot 'same.json'
    & $comparer -BaselinePath $InventoryPath -CandidatePath $InventoryPath -OutputPath $sameOutput | Out-Host
    $same = Get-Content -Raw -LiteralPath $sameOutput | ConvertFrom-Json
    if ($same.shaderDelta.addedCount -ne 0 -or $same.shaderDelta.removedCount -ne 0) {
        throw 'An inventory compared with itself produced a shader delta.'
    }
    if ($same.semanticDelta.addedCount -ne 0 -or $same.semanticDelta.removedCount -ne 0) {
        throw 'An inventory compared with itself produced a semantic delta.'
    }

    $synthetic = Get-Content -Raw -LiteralPath $InventoryPath | ConvertFrom-Json
    $synthetic.capture.captureId = 'synthetic-regional-delta'
    $removedShader = @($synthetic.capture.shaders | Where-Object stage -eq 'vs' | Select-Object -First 1)[0]
    $synthetic.capture.shaders = @($synthetic.capture.shaders | Where-Object shader -ne $removedShader.shader)
    $synthetic.capture.shaders += [pscustomobject]@{
        shader = 'ffffffffffffffff-ps'
        hash = 'ffffffffffffffff'
        stage = 'ps'
        binary = 'dxbc/ffffffffffffffff-ps.bin'
        assembly = 'assembly/ffffffffffffffff-ps.asm'
        originalDisassemblerHeaderRetained = $true
    }
    $synthetic.capture.stageShaderCounts.vs--
    $synthetic.capture.stageShaderCounts.ps++

    $removedMatch = @($synthetic.capture.semanticMatches)[0]
    $synthetic.capture.semanticMatches = @($synthetic.capture.semanticMatches |
        Where-Object { "$($_.descriptor)|$($_.hash)-$($_.stage)" -ne "$($removedMatch.descriptor)|$($removedMatch.hash)-$($removedMatch.stage)" })
    $synthetic.capture.semanticMatches += [pscustomobject]@{
        descriptor = 'synthetic-regional-pass'
        family = 'synthetic'
        displayName = 'Synthetic regional pass'
        hash = 'ffffffffffffffff'
        stage = 'ps'
        shaderModel = 'ps_5_0'
        semanticChecksPassed = 1
    }

    $syntheticPath = Join-Path $temporaryRoot 'synthetic.json'
    $synthetic | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $syntheticPath -Encoding utf8
    $deltaOutput = Join-Path $temporaryRoot 'delta.json'
    & $comparer -BaselinePath $InventoryPath -CandidatePath $syntheticPath -OutputPath $deltaOutput | Out-Host
    $delta = Get-Content -Raw -LiteralPath $deltaOutput | ConvertFrom-Json
    if ($delta.shaderDelta.addedCount -ne 1 -or $delta.shaderDelta.removedCount -ne 1) {
        throw 'Synthetic shader additions/removals were not detected.'
    }
    if ($delta.shaderDelta.addedStageCounts.ps -ne 1 -or $delta.shaderDelta.removedStageCounts.vs -ne 1) {
        throw 'Synthetic per-stage deltas were not detected.'
    }
    if ($delta.semanticDelta.addedCount -ne 1 -or $delta.semanticDelta.removedCount -ne 1) {
        throw 'Synthetic semantic additions/removals were not detected.'
    }
    if ('ffffffffffffffff-ps' -notin @($delta.shaderDelta.added)) {
        throw 'Synthetic shader is absent from the added list.'
    }

    Write-Host 'PASS: same-capture and synthetic regional inventory deltas are correct.'
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

