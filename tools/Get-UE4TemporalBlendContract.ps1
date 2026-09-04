[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AssemblyPath,
    [Parameter(Mandatory)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$assemblyFull = (Resolve-Path -LiteralPath $AssemblyPath).Path
$outputFull = if ([IO.Path]::IsPathRooted($OutputPath)) {
    [IO.Path]::GetFullPath($OutputPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
}
if (-not $outputFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must remain inside the project workspace: $outputFull"
}

function Split-DxbcOperands([string]$Text) {
    $parts = [Collections.Generic.List[string]]::new()
    $start = 0
    $depth = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        switch ($Text[$index]) {
            { $_ -in @('(', '[') } { $depth++; break }
            { $_ -in @(')', ']') } { $depth--; break }
            ',' {
                if ($depth -eq 0) {
                    $parts.Add($Text.Substring($start, $index - $start).Trim())
                    $start = $index + 1
                }
                break
            }
        }
    }
    if ($start -lt $Text.Length) { $parts.Add($Text.Substring($start).Trim()) }
    @($parts)
}

function Get-RegisterBase([string]$Operand) {
    $match = [regex]::Match($Operand, '(?i)(?<register>r\d+)')
    if ($match.Success) { return $match.Groups['register'].Value.ToLowerInvariant() }
    $null
}

function Get-LiteralValues([string]$Operand) {
    $match = [regex]::Match($Operand.Trim(), '^l\((?<values>[^\)]*)\)$')
    if (-not $match.Success) { return @() }
    $values = [Collections.Generic.List[double]]::new()
    foreach ($token in $match.Groups['values'].Value -split ',\s*') {
        $parsed = 0.0
        if (-not [double]::TryParse($token, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            return @()
        }
        $values.Add($parsed)
    }
    @($values)
}

$lines = [IO.File]::ReadAllLines($assemblyFull)
$model = @($lines | Where-Object { $_ -match '^(?:vs|ps|cs|hs|ds|gs)_5_0\s*$' } | Select-Object -First 1)
if (-not $model.Count -or $model[0].Trim() -ne 'cs_5_0') {
    throw 'Temporal blend contract analysis currently requires a cs_5_0 assembly.'
}

$instructions = [Collections.Generic.List[object]]::new()
for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
    $trimmed = $lines[$lineIndex].Trim()
    if (-not $trimmed -or $trimmed.StartsWith('//')) { continue }
    $instructionMatch = [regex]::Match($trimmed, '^(?<opcode>\S+)(?:\s+(?<operands>.*))?$')
    if (-not $instructionMatch.Success) { continue }
    $opcode = $instructionMatch.Groups['opcode'].Value
    if ($opcode -match '^(?:cs_5_0|dcl_)') { continue }
    $operandText = $instructionMatch.Groups['operands'].Value
    $instructions.Add([pscustomobject]@{
        lineNumber = $lineIndex + 1
        opcode = $opcode
        operands = if ($operandText) { @(Split-DxbcOperands $operandText) } else { @() }
    })
}

$sampleIndex = -1
for ($index = 0; $index -lt $instructions.Count; $index++) {
    if ($instructions[$index].opcode -like 'sample_l_indexable(texture3d)*') { $sampleIndex = $index }
}

$differenceIndex = -1
if ($sampleIndex -ge 0) {
    for ($index = $sampleIndex + 1; $index -le [Math]::Min($sampleIndex + 5, $instructions.Count - 1); $index++) {
        $candidate = $instructions[$index]
        if ($candidate.opcode -eq 'add' -and $candidate.operands.Count -eq 3 -and $candidate.operands[1].Trim().StartsWith('-')) {
            $differenceIndex = $index
            break
        }
    }
}

$blendIndex = -1
$differenceRegister = $null
$currentRegister = $null
if ($differenceIndex -ge 0) {
    $difference = $instructions[$differenceIndex]
    $differenceRegister = Get-RegisterBase $difference.operands[0]
    $currentRegister = Get-RegisterBase $difference.operands[1]
    for ($index = $differenceIndex + 1; $index -le [Math]::Min($differenceIndex + 5, $instructions.Count - 1); $index++) {
        $candidate = $instructions[$index]
        if ($candidate.opcode -ne 'mad' -or $candidate.operands.Count -ne 4) { continue }
        $left = Get-RegisterBase $candidate.operands[1]
        $right = Get-RegisterBase $candidate.operands[2]
        if ($left -eq $differenceRegister -or $right -eq $differenceRegister) {
            $blendIndex = $index
            break
        }
    }
}

$status = 'unresolved'
$historyWeight = $null
$currentWeight = $null
$coefficientOperand = $null
$dynamicScaleFactors = @()
$reason = 'A bounded sample-difference-blend sequence was not resolved.'

if ($blendIndex -ge 0) {
    $blend = $instructions[$blendIndex]
    $leftBase = Get-RegisterBase $blend.operands[1]
    $coefficientOperand = if ($leftBase -eq $differenceRegister) { $blend.operands[2] } else { $blend.operands[1] }
    $literal = @(Get-LiteralValues $coefficientOperand)
    if ($literal.Count -and @($literal | Where-Object { [Math]::Abs($_ - $literal[0]) -gt 0.000001 }).Count -eq 0 -and $literal[0] -ge 0 -and $literal[0] -le 1) {
        $status = 'fixed'
        $historyWeight = [Math]::Round($literal[0], 8)
        $currentWeight = [Math]::Round(1.0 - $literal[0], 8)
        $reason = 'The history-difference coefficient is a fixed literal in the resolved blend instruction.'
    } elseif (Get-RegisterBase $coefficientOperand) {
        $status = 'dynamic'
        $coefficientRegister = Get-RegisterBase $coefficientOperand
        $scales = [Collections.Generic.List[double]]::new()
        for ($index = $blendIndex - 1; $index -ge [Math]::Max(0, $blendIndex - 8); $index--) {
            $candidate = $instructions[$index]
            if ($candidate.opcode -ne 'mul' -or $candidate.operands.Count -ne 3) { continue }
            if ((Get-RegisterBase $candidate.operands[0]) -ne $coefficientRegister) { continue }
            foreach ($operand in @($candidate.operands[1], $candidate.operands[2])) {
                foreach ($value in @(Get-LiteralValues $operand)) {
                    if (-not $scales.Contains($value)) { $scales.Add($value) }
                }
            }
        }
        $dynamicScaleFactors = @($scales)
        $reason = 'The history-difference coefficient is register-derived; a fixed steady-state recurrence cannot be assumed.'
    }
}

$store = @($instructions | Where-Object opcode -eq 'store_uav_typed' | Select-Object -Last 1)
$hashMatch = [regex]::Match([IO.Path]::GetFileName($assemblyFull), '(?i)(?<hash>[0-9a-f]{16})-(?:cs)(?:[_-][^\.]*)?\.(?:asm|txt)$')
$relativeSource = if ($assemblyFull.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    $assemblyFull.Substring($repoRoot.Length + 1).Replace('\', '/')
} else {
    $assemblyFull
}

$report = [ordered]@{
    schemaVersion = 1
    analyzer = 'independent-temporal-blend-contract'
    shader = [ordered]@{
        hash = if ($hashMatch.Success) { $hashMatch.Groups['hash'].Value.ToLowerInvariant() } else { $null }
        stage = 'cs'
        shaderModel = 'cs_5_0'
        source = $relativeSource
        sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyFull).Hash
    }
    temporalBlend = [ordered]@{
        status = $status
        historyWeight = $historyWeight
        currentWeight = $currentWeight
        dynamicScaleFactors = @($dynamicScaleFactors)
        steadyStateCompensationEligible = $status -eq 'fixed'
        reason = $reason
    }
    structuralEvidence = [ordered]@{
        historySample = if ($sampleIndex -ge 0) { [ordered]@{ line = $instructions[$sampleIndex].lineNumber; opcode = $instructions[$sampleIndex].opcode } } else { $null }
        historyDifference = if ($differenceIndex -ge 0) { [ordered]@{ line = $instructions[$differenceIndex].lineNumber; opcode = $instructions[$differenceIndex].opcode; destinationRegister = $differenceRegister; currentRegister = $currentRegister } } else { $null }
        temporalBlend = if ($blendIndex -ge 0) { [ordered]@{ line = $instructions[$blendIndex].lineNumber; opcode = $instructions[$blendIndex].opcode; coefficientKind = if ($status -eq 'fixed') { 'literal' } elseif ($status -eq 'dynamic') { 'register' } else { 'unresolved' } } } else { $null }
        volumeStore = if ($store.Count) { [ordered]@{ line = $store[0].lineNumber; opcode = $store[0].opcode } } else { $null }
    }
}

$outputDirectory = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
[IO.File]::WriteAllText($outputFull, ($report | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

Write-Output "Temporal blend status: $status"
if ($status -eq 'fixed') { Write-Output "Weights: current=$currentWeight history=$historyWeight" }
if ($status -eq 'dynamic') { Write-Output "Dynamic scale factors: $(@($dynamicScaleFactors) -join ', ')" }
Write-Output "Report: $outputFull"
