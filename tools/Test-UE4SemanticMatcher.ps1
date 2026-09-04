[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-semantic-matcher-test')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$matcher = Join-Path $repoRoot 'tools\Match-UE4SemanticPasses.ps1'
$fixtures = Join-Path $repoRoot 'src\Tests\Fixtures\UE4Semantic'
$reportPath = Join-Path $OutputDirectory 'report.json'

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
& $matcher -ShaderDirectory $fixtures -OutputPath $reportPath

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$matches = @($report.matches)
if ($report.licensedRegexDependency -ne $false) {
    throw 'Semantic matcher unexpectedly depends on licensed regex input.'
}
if ($report.shaders.scanned -ne 9) {
    throw "Expected nine shader fixtures, scanned $($report.shaders.scanned)."
}
if ($matches.Count -ne 8) {
    throw "Expected exactly eight semantic matches, found $($matches.Count)."
}
foreach ($expected in @(
    @{ descriptor = 'ue4-volumetric-scattering-history-sm5'; hash = '0000000000000002' },
    @{ descriptor = 'ue4-motion-blur-scene-color-resolve-ps-sm5'; hash = 'af6cd28a0108a18a' },
    @{ descriptor = 'ue4-screen-space-reflection-trace-resolve-ps-sm5'; hash = 'b2bc6059f9a39c7f' },
    @{ descriptor = 'ue4-reflection-environment-ssr-composite-ps-sm5'; hash = 'e2aa1c8cb39e0a55' },
    @{ descriptor = 'ue4-temporal-ssao-horizon-ps-sm5'; hash = 'a77b589dce5822d6' },
    @{ descriptor = 'ue4-volumetric-fog-grid-injection-ps-sm5'; hash = 'c25d7f5229662b97' },
    @{ descriptor = 'ue4-volumetric-fog-grid-injection-ps-sm5'; hash = 'cbc771ff8a37a0b3' },
    @{ descriptor = 'ue4-volumetric-scattering-history-sm5'; hash = 'ef7fe8d9c4e9ad15' }
)) {
    $actual = @($matches | Where-Object {
        $_.descriptor -eq $expected.descriptor -and $_.hash -eq $expected.hash
    })
    if ($actual.Count -ne 1) {
        throw "Expected one $($expected.descriptor) match for $($expected.hash), found $($actual.Count)."
    }
}
if (@($matches | Where-Object { $_.hash -eq '0000000000000001' }).Count) {
    throw 'Negative fixture matched a semantic descriptor.'
}
if (@($matches.evidence | ForEach-Object { $_ } | Where-Object { -not $_.satisfied }).Count) {
    throw 'A reported semantic match contains an unsatisfied check.'
}
if (@($matches.fastPathAdapters | ForEach-Object { $_ }) -notcontains 'FF7RemakeIntergrade') {
    throw 'Expected FF7 fast-path evidence was not reported.'
}
if (@($report.matchTimeouts).Count) {
    throw "Semantic matcher had $(@($report.matchTimeouts).Count) regex timeout(s)."
}

function Assert-DescriptorRejected {
    param(
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$ExpectedMessage
    )
    $caseRoot = Join-Path $OutputDirectory ("negative-" + $Name)
    $descriptorRoot = Join-Path $caseRoot 'descriptors'
    New-Item -ItemType Directory -Path $descriptorRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\schema.json') -Destination $descriptorRoot -Force
    $descriptor = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\motion-blur-scene-color-resolve-ps-sm5.json') | ConvertFrom-Json
    & $Mutate $descriptor
    $descriptor | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $descriptorRoot 'invalid.json') -Encoding UTF8
    $caught = $null
    try {
        & $matcher -ShaderDirectory $fixtures -DescriptorDirectory $descriptorRoot -OutputPath (Join-Path $caseRoot 'report.json') | Out-Null
    }
    catch {
        $caught = $_.Exception.Message
    }
    if (-not $caught) { throw "Negative descriptor case '$Name' was unexpectedly accepted." }
    if ($caught -notmatch $ExpectedMessage) {
        throw "Negative descriptor case '$Name' failed for the wrong reason: $caught"
    }
}

Assert-DescriptorRejected 'additional-property' {
    param($descriptor)
    $descriptor | Add-Member -NotePropertyName unexpectedProperty -NotePropertyValue $true
} 'unsupported property'
Assert-DescriptorRejected 'duplicate-check-id' {
    param($descriptor)
    $descriptor.semanticSignature.checks = @($descriptor.semanticSignature.checks[0], $descriptor.semanticSignature.checks[0])
} 'duplicate semantic check id'
Assert-DescriptorRejected 'invalid-regex' {
    param($descriptor)
    $descriptor.semanticSignature.checks[0].pattern = '('
} 'invalid regex'
Assert-DescriptorRejected 'invalid-count-range' {
    param($descriptor)
    $descriptor.semanticSignature.checks[0].minCount = 2
    $descriptor.semanticSignature.checks[0].maxCount = 1
} 'maxCount is less than minCount'

$collisionRoot = Join-Path $OutputDirectory 'negative-hash-collision'
$collisionDescriptors = Join-Path $collisionRoot 'descriptors'
New-Item -ItemType Directory -Path $collisionDescriptors -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\schema.json') -Destination $collisionDescriptors -Force
$first = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\motion-blur-scene-color-resolve-ps-sm5.json') | ConvertFrom-Json
$second = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\Engine\UE4\PassDescriptors\temporal-ssao-horizon-ps-sm5.json') | ConvertFrom-Json
$second.hashFastPaths[0].hash = $first.hashFastPaths[0].hash
$first | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $collisionDescriptors 'first.json') -Encoding UTF8
$second | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $collisionDescriptors 'second.json') -Encoding UTF8
$collisionError = $null
try {
    & $matcher -ShaderDirectory $fixtures -DescriptorDirectory $collisionDescriptors -OutputPath (Join-Path $collisionRoot 'report.json') | Out-Null
}
catch {
    $collisionError = $_.Exception.Message
}
if (-not $collisionError -or $collisionError -notmatch 'assigned to multiple descriptors') {
    throw "Known-hash collision was not rejected correctly: $collisionError"
}

Write-Output 'UE4 semantic matcher tests passed.'
Write-Output "Report: $reportPath"
