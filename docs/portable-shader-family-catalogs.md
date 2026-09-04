# Portable shader-family catalogs

## Purpose

The catalog format keeps three concepts separate:

1. a logical rendering job, such as local-light evaluation;
2. one game/API implementation of that job;
3. the exact or structural identities accepted for that implementation.

This separation is required because related engine work does not imply
interchangeable bytecode. Shader Injector v2.2.1 performs Rebirth local-light
evaluation in a D3D12 `ps_6_6` shader. The verified Remake adapter performs the
relevant local-light/contact work in five D3D11 `cs_5_0` specializations. The
effect intent can be related while stage, resources, bindings, bytecode, and
replacement generation remain backend-specific.

The schema is `src/Engine/ShaderFamilies/schema.json`.

Run the complete offline family-system verification with:

```powershell
& tools\Test-PortableShaderFamilySystem.ps1
```

This rebuilds and validates the Rebirth and Remake catalogs, cross-game
relations, semantic discovery, alias review ledger, family-gated DXBC
publisher, and the non-installing DXVK build pipeline. It performs no game
installation and no network acquisition.

## Identity models currently represented

- `shader-injector-dxil-analysis-v1` preserves the author's reflected DXIL
  interface, resource, constant-buffer, execution, portable-reflection,
  semantic-instruction, and cross-version identities. One logical family may
  retain several legitimate identity variants.
- `3dmigoto-dxbc-fnv1-v1` preserves the exact stage-aware 64-bit 3Dmigoto hash
  of captured DXBC. It is a verified fast path, not yet a structural universal
  rule.
- `ue4-dxbc-regex-semantic-v1` preserves bounded, timeout-controlled DXBC
  assembly predicates plus any already reviewed exact hashes. It is used for
  structural discovery across regional shader variants; a structural match is
  evidence for review, not permission to replace a shader at runtime.

Adding a new API does not weaken either model. A D3D9 implementation can later
use its own token/assembly identity model beneath the same logical family.

## Generated catalogs

Rebuild and validate the Rebirth donor catalog:

```powershell
& tools\Test-RebirthShaderFamilyCatalog.ps1
```

This verifies the two original archives and exports 44 targets in 11 families
to `artifacts/analysis/rebirth-shader-injector-v2.2.1-family-catalog.json`.
The output is deterministic; two regenerations produce the same bytes and
SHA-256.

Rebuild and validate the current Remake catalog:

```powershell
& tools\Test-RemakeShaderFamilyCatalog.ps1
```

This first runs the authoritative header/evidence audit, then exports all 29
currently verified shaders in 10 families to
`artifacts/analysis/ff7-remake-intergrade-verified-family-catalog.json`.
Skinned/static casters, sampled/direct depth writers, material/GBuffer passes,
and the five local-light compute specializations remain distinct.

Rebuild and validate the UE4 semantic catalog:

```powershell
& tools\Test-UE4SemanticShaderFamilyCatalog.ps1
```

This exports six bounded semantic families and seven exact fast paths to
`artifacts/analysis/ue4-dxbc-semantic-family-catalog.json`. The matcher in
`tools/Match-DxbcShaderFamilyCatalog.ps1` consumes that portable catalog rather
than hard-coding a game-specific shader list.

## Structural discovery and learned aliases

Run the complete Remake regional-discovery regression with:

```powershell
& tools\Test-RemakeShaderFamilyAliasCandidates.ps1
```

The test scans the immutable 184-shader contact-area baseline through the
semantic catalog. The current result is eight structural matches with zero
regex timeouts. Seven are existing exact targets; the remaining shader,
`EDA405F2D455D5C7-ps`, is emitted to
`artifacts/analysis/ff7r-contact-area-baseline-20260831-alias-candidates.json`
as a review-only alias candidate for the motion-blur/scene-color-resolve
family.

Candidate generation is deliberately fail-closed. It verifies the catalog ID
and SHA-256 pinned by the scan report, requires the original disassembler
header and shader model evidence, and writes `catalogMutation=false` and
`runtimeEligible=false`. A human-reviewed promotion step is still required
before the hash can enter a runtime replacement catalog.

The durable family-alias review state is stored separately in
`src/Adapters/FF7RemakeIntergrade/shader-family-alias-decisions.json` and
validated with:

```powershell
& tools\Test-ShaderFamilyAliasDecisionLedger.ps1
```

The ledger pins both the semantic catalog and the byte-deterministic candidate
artifact. Every current candidate must have exactly one pending, accepted, or
rejected entry. Accepted and rejected entries additionally require a reviewer,
UTC review time, rationale, and hash-verified evidence. Pending entries cannot
be treated as runtime eligible. This family-identity decision is distinct from
the later per-game runtime review workspace: accepting an alias only establishes
that a captured shader belongs to a family; it does not approve an injected
effect.

Once a ledger entry has been explicitly accepted with adapter, version group,
reviewer, UTC review time, rationale, and hash-pinned evidence, publish a
derived catalog with:

```powershell
& tools\Publish-ReviewedShaderFamilyAliases.ps1 `
    -CatalogPath artifacts\analysis\ue4-dxbc-semantic-family-catalog.json `
    -DecisionLedgerPath src\Adapters\FF7RemakeIntergrade\shader-family-alias-decisions.json `
    -OutputPath artifacts\analysis\ue4-dxbc-semantic-reviewed-aliases.json
```

The publisher never edits the base catalog. It adds each accepted alias to both
the structural identity's `hashFastPaths` and the exact resolver's `targets`,
then strictly validates the derived catalog. Pending or rejected entries are
not published, and an all-pending ledger fails by default. The regression in
`tools/Test-PublishReviewedShaderFamilyAliases.ps1` proves base-catalog
isolation, synchronized indexes, pending rejection, exact resolution, and
byte-deterministic output.

The promotion-to-builder boundary is covered with real captured data by
`tools/Test-ReviewedAliasDxvkEndToEnd.ps1`. It proves the pending hash cannot
resolve through the base catalog, then uses an isolated accepted fixture to
publish and compile the retained `EDA405F2D455D5C7-ps` HLSL against its exact
captured DXBC. The capture has stripped RDEF resource metadata, so compatibility
is verified against reflected signatures and executable binding declarations;
an altered resource declaration is rejected. The produced manifest remains
`runtimeEligible=false` and `installed=false`.

## Explicit cross-game decisions

The Remake inventory feeding this decision layer is byte-deterministic. It
stores workspace-relative provenance rather than volatile UTC timestamps or
absolute machine paths, and its regression test generates it twice and rejects
any hash drift. A changed catalog hash therefore represents changed reviewed
content rather than the time or machine on which the catalog was regenerated.

`src/Adapters/FF7RemakeIntergrade/rebirth-family-relations.json` records
reviewed relations between the two hash-pinned catalogs. Validate it with:

```powershell
& tools\Test-RemakeRebirthFamilyRelations.ps1
```

Every Rebirth donor family must appear exactly once as either a promoted
relation or an unresolved decision. Currently only `LocalLight` is promoted to
Remake's `tiled-surface-light-evaluation` family. It is a semantic adapter
relation, not a direct shader replacement. The remaining ten donor families
state the scene and evidence required before promotion.

This is the fail-closed bridge from one-area hand work to a universal
generator: exact hashes remain useful fast paths, structural variants remain
explicit, and no family is inferred merely because its name sounds similar.

## Exact fast-path consumer

`tools/Resolve-ShaderFamilyCatalogTarget.ps1` resolves one stage/hash pair to a
single reviewed family implementation. It rejects malformed hashes and catalog
collisions; wrong-stage and unknown hashes can either fail or return no match
for a later structural-discovery path. The offline DXVK replacement builder can
consume this resolver through `-FamilyCatalogPath`, preserving the reviewed
classification and catalog hash in its output manifest.
