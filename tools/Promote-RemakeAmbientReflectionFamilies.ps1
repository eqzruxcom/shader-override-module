[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$classificationPath = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\verified-shader-classifications.json'
$relationsPath = Join-Path $root 'src\Adapters\FF7RemakeIntergrade\rebirth-family-relations.json'
$remakeTestPath = Join-Path $root 'tools\Test-RemakeVerifiedShaderClassifications.ps1'
$catalogTestPath = Join-Path $root 'tools\Test-RemakeShaderFamilyCatalog.ps1'
$relationsTestPath = Join-Path $root 'tools\Test-RemakeRebirthFamilyRelations.ps1'
$catalogPath = Join-Path $root 'artifacts\analysis\ff7-remake-intergrade-verified-family-catalog.json'
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$backupRoot = Join-Path $root "artifacts\migrations\$stamp-promote-remake-ambient-reflection-families"
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Replace-Exact([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne 1) { throw "$Label expected one exact occurrence, found $count" }
    return $Text.Replace($Old, $New)
}

$protected = @($classificationPath, $relationsPath, $remakeTestPath, $catalogTestPath, $relationsTestPath, $catalogPath)
foreach ($path in $protected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file missing: $path" }
    Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot (Split-Path -Leaf $path))
}

$classification = Get-Content -Raw -LiteralPath $classificationPath | ConvertFrom-Json
if (@($classification.families).Count -ne 10) { throw 'Expected the pre-promotion ten-family Remake classification.' }
$existingFamilyIds = @($classification.families.familyId)
foreach ($id in @('temporal-screen-space-ambient-occlusion','screen-space-reflection-trace-resolve','reflection-indirect-composite')) {
    if ($id -in $existingFamilyIds) { throw "Family already exists: $id" }
}

$newFamilies = @(
    [pscustomobject][ordered]@{
        familyId = 'temporal-screen-space-ambient-occlusion'
        stage = 'ps'
        role = 'native temporal screen-space ambient-occlusion evaluation and history-aware output'
        status = 'verified-live-output-isolation-and-strength-control'
        insertionEligibility = 'eligible-for-native-ao-adapter-not-contact-shadow-or-ssgi'
        hashes = @([pscustomobject][ordered]@{
            hash = 'a77b589dce5822d6'
            visualObservation = 'live output-channel isolation and native AO strength control verified; not evidence of Rebirth SSGI equivalence'
        })
        evidence = @(
            'docs/shader-coverage-audit-2026-08-31.md',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/a77b589dce5822d6-ps.asm'
        )
        constraints = @(
            'Keep native temporal SSAO separate from Rebirth ReflectionEnvironment SSGI/AO.',
            'This pass is not a local-light contact-shadow evaluator.',
            'Any replacement must preserve temporal history, channel packing, and downstream consumers.'
        )
    },
    [pscustomobject][ordered]@{
        familyId = 'screen-space-reflection-trace-resolve'
        stage = 'ps'
        role = 'screen-space reflection trace and resolve variants'
        status = 'verified-resource-flow-and-retained-header-family'
        insertionEligibility = 'eligible-only-as-complete-ssr-family-after-live-visual-gate'
        hashes = @(
            [pscustomobject][ordered]@{
                hash = 'b2bc6059f9a39c7f'
                visualObservation = 'resource flow and amplified reflection response verified'
            },
            [pscustomobject][ordered]@{
                hash = '8c9e92a0895efcdc'
                visualObservation = 'exact old-Remake Helix header identifies an SSR variant with a dithering exception; not executed in saved indoor frames'
            }
        )
        evidence = @(
            'docs/shader-coverage-audit-2026-08-31.md',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/b2bc6059f9a39c7f-ps.asm',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/8c9e92a0895efcdc-ps.asm',
            'reference/HelixMod-FF7R/FixFiles/ShaderFixesDM/8c9e92a0895efcdc-ps.txt'
        )
        constraints = @(
            'Treat the two hashes as SSR variants, not interchangeable bytecode.',
            'Preserve the downstream reflection-environment composite and native material masks.',
            'Promotion of a visual control still requires a strong reflection-scene A/B test.'
        )
    },
    [pscustomobject][ordered]@{
        familyId = 'reflection-indirect-composite'
        stage = 'ps'
        role = 'material-aware reflection-environment, SSR, and indirect-light composition variants'
        status = 'verified-resource-flow-and-structural-brdf-family'
        insertionEligibility = 'eligible-consumer-boundary-after-material-ui-and-live-visual-gates'
        hashes = @(
            [pscustomobject][ordered]@{
                hash = 'e2aa1c8cb39e0a55'
                visualObservation = 'verified reflection-environment and SSR composite producer/consumer boundary'
            },
            [pscustomobject][ordered]@{
                hash = 'c62607f2631cf47e'
                visualObservation = 'cache-unique sibling with the same shading-model BRDF signature and final scaling; full-GBuffer/precomputed-lighting inputs'
            }
        )
        evidence = @(
            'docs/shader-coverage-audit-2026-08-31.md',
            'docs/intergrade-ssgi-character-material-compatibility.md',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/e2aa1c8cb39e0a55-ps.asm',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/c62607f2631cf47e-ps.asm'
        )
        constraints = @(
            'This is the downstream material-aware composite boundary, not proof that Remake has Rebirth SampleGI or the same SSGI producer.',
            'Do not fold temporal SSAO into this family merely because the donor combines AO and reflection-environment work.',
            'Any injected indirect light must preserve material/shading-model branches, SSR input, alpha, and UI separation.'
        )
    }
)
$classification.families = @($classification.families) + $newFamilies
Write-Utf8NoBom $classificationPath (($classification | ConvertTo-Json -Depth 12) + [Environment]::NewLine)

$remakeTest = Get-Content -Raw -LiteralPath $remakeTestPath
$anchor = '$missingIds = @($manifest.missingFamilies.familyId)'
$checks = @'
$ambientSpecs = @(
    [pscustomobject]@{ Family='temporal-screen-space-ambient-occlusion'; Stage='ps'; Hashes=@('a77b589dce5822d6'); Eligibility='eligible-for-native-ao-adapter-not-contact-shadow-or-ssgi' },
    [pscustomobject]@{ Family='screen-space-reflection-trace-resolve'; Stage='ps'; Hashes=@('8c9e92a0895efcdc','b2bc6059f9a39c7f'); Eligibility='eligible-only-as-complete-ssr-family-after-live-visual-gate' },
    [pscustomobject]@{ Family='reflection-indirect-composite'; Stage='ps'; Hashes=@('c62607f2631cf47e','e2aa1c8cb39e0a55'); Eligibility='eligible-consumer-boundary-after-material-ui-and-live-visual-gates' }
)
foreach ($spec in $ambientSpecs) {
    $family = @($manifest.families | Where-Object familyId -eq $spec.Family)
    if ($family.Count -ne 1 -or [string]$family[0].stage -ne $spec.Stage -or [string]$family[0].insertionEligibility -ne $spec.Eligibility) {
        throw "Ambient/reflection family contract changed: $($spec.Family)"
    }
    if (Compare-Object @($spec.Hashes | Sort-Object) @($family[0].hashes.hash | Sort-Object)) {
        throw "Ambient/reflection family identities changed: $($spec.Family)"
    }
}

'@
$remakeTest = Replace-Exact $remakeTest $anchor ($checks + $anchor) 'Remake classification test insertion'
Write-Utf8NoBom $remakeTestPath $remakeTest

$catalogTest = Get-Content -Raw -LiteralPath $catalogTestPath
$catalogTest = Replace-Exact $catalogTest "`$catalog.families.Count -ne 10" "`$catalog.families.Count -ne 13" 'Catalog family count'
$catalogTest = Replace-Exact $catalogTest "`$sourceKeys.Count -ne 29" "`$sourceKeys.Count -ne 34" 'Catalog shader count'
$catalogTest = Replace-Exact $catalogTest "    'tiled-surface-light-evaluation'" "    'tiled-surface-light-evaluation',`r`n    'temporal-screen-space-ambient-occlusion',`r`n    'screen-space-reflection-trace-resolve',`r`n    'reflection-indirect-composite'" 'Catalog required family list'
$catalogTest = Replace-Exact $catalogTest 'preserves all 29 exact identities' 'preserves all 34 exact identities' 'Catalog success message'
Write-Utf8NoBom $catalogTestPath $catalogTest

& (Join-Path $root 'tools\Export-RemakeShaderFamilyCatalog.ps1') -OutputPath $catalogPath

$relations = Get-Content -Raw -LiteralPath $relationsPath | ConvertFrom-Json
if (@($relations.relations).Count -ne 1 -or @($relations.unresolved).Count -ne 10) { throw 'Expected pre-promotion 1/10 family relation split.' }
$remove = @('ssr','reflection-environment')
$relations.unresolved = @($relations.unresolved | Where-Object { [string]$_.from.family -notin $remove })
$relations.relations = @($relations.relations) + @(
    [pscustomobject][ordered]@{
        from = [pscustomobject][ordered]@{ catalog='ff7-rebirth-shader-injector-v2-2-1'; family='ssr' }
        to = [pscustomobject][ordered]@{ catalog='ff7-remake-intergrade-verified-area-20260831'; family='screen-space-reflection-trace-resolve' }
        relationType = 'semantic-role-adapter'
        status = 'verified-role-boundary-pending-effect-port-and-live-visual-acceptance'
        evidence = @(
            'docs/shader-coverage-audit-2026-08-31.md',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/b2bc6059f9a39c7f-ps.asm',
            'reference/HelixMod-FF7R/FixFiles/ShaderFixesDM/8c9e92a0895efcdc-ps.txt'
        )
        constraints = @(
            'The semantic role maps, but Rebirth and Remake hashes, constants, resources, and output contracts are not portable.',
            'Both known Remake SSR variants must remain represented; the unexecuted variant is retained from exact Helix header evidence.',
            'The downstream Remake reflection/indirect composite is a separate family and must be preserved.'
        )
    },
    [pscustomobject][ordered]@{
        from = [pscustomobject][ordered]@{ catalog='ff7-rebirth-shader-injector-v2-2-1'; family='reflection-environment' }
        to = [pscustomobject][ordered]@{ catalog='ff7-remake-intergrade-verified-area-20260831'; family='reflection-indirect-composite' }
        relationType = 'partial-semantic-role-adapter'
        status = 'verified-remake-consumer-boundary-pending-producer-adapter-and-live-visual-acceptance'
        evidence = @(
            'docs/shader-coverage-audit-2026-08-31.md',
            'docs/intergrade-ssgi-character-material-compatibility.md',
            'artifacts/validation-captures/ff7r-contact-area-baseline-20260831/assembly/e2aa1c8cb39e0a55-ps.asm'
        )
        constraints = @(
            'Rebirth performs this family in D3D12 compute shaders; Remake exposes the verified downstream boundary in D3D11 pixel shaders.',
            'This relation covers reflection/indirect composition only; it does not claim that Rebirth SSGI/AO and Remake temporal SSAO are equivalent.',
            'A Remake indirect-light producer still requires separate proof before an SSGI port can be promoted.'
        )
    }
)
$remakeReference = @($relations.catalogs | Where-Object id -eq 'ff7-remake-intergrade-verified-area-20260831')
if ($remakeReference.Count -ne 1) { throw 'Remake catalog reference is missing or ambiguous.' }
$remakeReference[0].sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $catalogPath).Hash.ToUpperInvariant()
Write-Utf8NoBom $relationsPath (($relations | ConvertTo-Json -Depth 12) + [Environment]::NewLine)

$relationsTest = Get-Content -Raw -LiteralPath $relationsTestPath
$relationsTest = Replace-Exact $relationsTest "`$relations.relations.Count -ne 1 -or `$relations.unresolved.Count -ne 10" "`$relations.relations.Count -ne 3 -or `$relations.unresolved.Count -ne 8" 'Relation decision counts'
$relationsTest = Replace-Exact $relationsTest "`$verified = `$relations.relations[0]" "`$verified = @(`$relations.relations | Where-Object { `$_.from.family -eq 'local-light' })[0]" 'Local relation selection'
$relationAnchor = "foreach (`$required in @('directional-light','local-light-ies')) {"
$relationChecks = @'
$ssr = @($relations.relations | Where-Object { $_.from.family -eq 'ssr' })
if ($ssr.Count -ne 1 -or $ssr[0].to.family -ne 'screen-space-reflection-trace-resolve') { throw 'Verified SSR relation regression' }
$reflection = @($relations.relations | Where-Object { $_.from.family -eq 'reflection-environment' })
if ($reflection.Count -ne 1 -or $reflection[0].to.family -ne 'reflection-indirect-composite' -or $reflection[0].relationType -ne 'partial-semantic-role-adapter') {
    throw 'Verified partial reflection-environment relation regression'
}
if (@($relations.unresolved | Where-Object { $_.from.family -in @('ssr','reflection-environment') }).Count -ne 0) {
    throw 'Promoted SSR/reflection families remain duplicated in unresolved decisions'
}

'@
$relationsTest = Replace-Exact $relationsTest $relationAnchor ($relationChecks + $relationAnchor) 'Relation test insertion'
$relationsTest = Replace-Exact $relationsTest 'only LocalLight is currently promoted.' 'LocalLight, SSR, and the partial ReflectionEnvironment consumer boundary are promoted.' 'Relation success message'
Write-Utf8NoBom $relationsTestPath $relationsTest

$receipt = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    result = 'promoted-three-remake-families-and-two-cross-game-relations'
    backupDirectory = $backupRoot
    classification = [ordered]@{ path=$classificationPath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $classificationPath).Hash }
    remakeCatalog = [ordered]@{ path=$catalogPath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $catalogPath).Hash }
    relations = [ordered]@{ path=$relationsPath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $relationsPath).Hash }
}
Write-Utf8NoBom (Join-Path $backupRoot 'receipt.json') (($receipt | ConvertTo-Json -Depth 6) + [Environment]::NewLine)
Write-Host "PASS: promoted temporal SSAO, SSR, and reflection/indirect Remake families; mapped Rebirth SSR and partial ReflectionEnvironment boundaries. Backup: $backupRoot"
