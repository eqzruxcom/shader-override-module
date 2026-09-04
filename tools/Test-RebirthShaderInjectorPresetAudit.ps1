[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Split-Path $PSScriptRoot -Parent
$analyzer = Join-Path $PSScriptRoot 'Analyze-RebirthShaderInjectorPresets.ps1'
$reportPath = Join-Path $workspace 'artifacts\analysis\rebirth-shader-injector-v2.2.1-preset-audit.json'

& $analyzer -OutputPath $reportPath
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($null -ne $report.PSObject.Properties['GeneratedUtc']) { throw 'Audit must remain deterministic and must not embed a generation timestamp' }

if ($report.Archives.Performance.FileCount -ne 158 -or $report.Archives.MaximumQuality.FileCount -ne 158) { throw 'Archive file-count regression' }
if ($report.Comparison.IdenticalFileCount -ne 143 -or $report.Comparison.DifferentFileCount -ne 15) { throw 'Preset comparison-count regression' }
if ($report.Comparison.DifferentSourcePaths.Count -ne 3 -or $report.Comparison.DifferentCompiledBlobPaths.Count -ne 12) { throw 'Preset source/blob split regression' }
if ($report.FingerprintInventory.Count -ne 44) { throw 'Fingerprint-count regression' }
if ($report.FingerprintInventory.Families.Count -ne 11 -or $report.FingerprintInventory.VersionGroups.Count -ne 4) { throw 'Family/version-count regression' }
if ($report.FingerprintInventory.StageCounts.PixelShader -ne 36 -or $report.FingerprintInventory.StageCounts.ComputeShader -ne 8) { throw 'Shader-stage regression' }

$stableCrossVersionFamilies = @('DirectionalLight', 'LocalLight', 'LocalLightIES', 'SampleGI')
foreach ($familyName in $stableCrossVersionFamilies) {
    $family = @($report.FingerprintInventory.FamilyIdentityVariation | Where-Object { $_.Family -eq $familyName })
    if ($family.Count -ne 1 -or $family[0].VersionTargetCount -ne 4 -or $family[0].CrossVersionIdentityCount -ne 1) {
        throw "Stable cross-version family regression: $familyName"
    }
}
$water = @($report.FingerprintInventory.FamilyIdentityVariation | Where-Object { $_.Family -eq 'WaterA' })
if ($water.Count -ne 1 -or $water[0].CrossVersionIdentityCount -le 1) { throw 'Expected WaterA to demonstrate legitimate within-family identity variation' }

$expectedDefines = @(
    'SSGI_AMBIENT_OCCLUSION',
    'SSGI_BOUNCE_LIGHT',
    'CHARACTER_DOMINANT_DIRECTION_SHADING',
    'AUTO_EXPOSURE'
)
$actualDefines = @($report.FunctionalPresetDifferences.Define | Sort-Object)
if (@(Compare-Object ($expectedDefines | Sort-Object) $actualDefines).Count -ne 0) { throw 'Functional feature-set regression' }
foreach ($feature in $report.FunctionalPresetDifferences) {
    if ($feature.PerformanceEnabled -or -not $feature.MaximumQualityEnabled) { throw "Feature-state regression: $($feature.Define)" }
}

$unexpectedDirectionalOrLocalDifference = @($report.Comparison.DifferentPaths | Where-Object { $_ -match 'DirectionalLight|LocalLight' })
if ($unexpectedDirectionalOrLocalDifference.Count -ne 0) { throw 'Lighting/contact target unexpectedly differs between presets' }

Write-Host 'PASS: Rebirth Shader Injector v2.2.1 preset audit is reproducible and internally consistent.'
