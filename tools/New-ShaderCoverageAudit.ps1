[CmdletBinding()]
param(
    [string]$ShaderCacheDirectory,
    [string]$HelixReferenceDirectory,
    [string]$DonorDirectory,
    [string]$UniversalMatchReport,
    [string]$ShaderMapPath,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ShaderCacheDirectory) {
    $ShaderCacheDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderCache'
}
if (-not $HelixReferenceDirectory) {
    $HelixReferenceDirectory = Join-Path $projectRoot 'reference\HelixMod-FF7R\FixFiles\ShaderFixesDM'
}
if (-not $DonorDirectory) {
    $DonorDirectory = Join-Path $projectRoot 'reference\ShaderInjector\ModifiedShaders'
}
if (-not $UniversalMatchReport) {
    $UniversalMatchReport = Join-Path $projectRoot 'artifacts\intergrade-current-area-ue4-family-matches.json'
}
if (-not $ShaderMapPath) {
    $ShaderMapPath = Join-Path $projectRoot 'src\Adapters\FF7RemakeIntergrade\shader-map.json'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot 'artifacts\shader-coverage-audit-20260831-v1'
}

foreach ($requiredPath in @(
    $ShaderCacheDirectory,
    $HelixReferenceDirectory,
    $DonorDirectory,
    $UniversalMatchReport,
    $ShaderMapPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required audit input does not exist: $requiredPath"
    }
}

function Get-ShaderIdentity {
    param(
        [Parameter(Mandatory)][IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$Pattern
    )

    if ($File.Name -notmatch $Pattern) {
        return $null
    }

    [pscustomobject]@{
        hash = $Matches.hash.ToLowerInvariant()
        stage = $Matches.stage.ToLowerInvariant()
        file = $File.FullName
    }
}

$liveShaders = @(
    Get-ChildItem -LiteralPath $ShaderCacheDirectory -File -Filter '*_replace.txt' |
        ForEach-Object {
            Get-ShaderIdentity -File $_ -Pattern '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|gs|hs|ds)_replace\.txt$'
        } |
        Where-Object { $_ } |
        Sort-Object stage, hash -Unique
)

$helixShaders = @(
    Get-ChildItem -LiteralPath $HelixReferenceDirectory -File -Filter '*.txt' |
        ForEach-Object {
            Get-ShaderIdentity -File $_ -Pattern '^(?<hash>[0-9a-fA-F]{16})-(?<stage>vs|ps|cs|gs|hs|ds)\.txt$'
        } |
        Where-Object { $_ } |
        Sort-Object stage, hash -Unique
)

$helixByIdentity = @{}
foreach ($shader in $helixShaders) {
    $helixByIdentity["$($shader.hash)-$($shader.stage)"] = $shader
}

$exactHelixIntersection = @(
    foreach ($shader in $liveShaders) {
        $identity = "$($shader.hash)-$($shader.stage)"
        if ($helixByIdentity.ContainsKey($identity)) {
            [pscustomobject]@{
                hash = $shader.hash
                stage = $shader.stage
                liveFile = $shader.file
                helixFile = $helixByIdentity[$identity].file
            }
        }
    }
)

$shaderMap = Get-Content -Raw -LiteralPath $ShaderMapPath | ConvertFrom-Json
$verifiedByIdentity = @{}
foreach ($pass in @($shaderMap.passes)) {
    foreach ($hash in @($pass.hashes)) {
        if (-not $hash) {
            continue
        }
        $identity = "$($hash.ToLowerInvariant())-$($pass.stage.ToLowerInvariant())"
        if (-not $verifiedByIdentity.ContainsKey($identity)) {
            $verifiedByIdentity[$identity] = [Collections.Generic.List[string]]::new()
        }
        $verifiedByIdentity[$identity].Add([string]$pass.id)
    }
}

$observedRoles = @{
    '0a3eb7cbd1651d9e-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '2db6a6321b86350b-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '318bb683297e3eb7-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '37efcd402da50bcb-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '54c7eb58e6a47dd1-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '5f888f1fd6479e44-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '611d1e0b0c1df60b-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '62d0b4e75495e831-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '633b722e5e888b74-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '7af16907968715c5-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '8d250d0c3e94f3c3-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '951f2cf9e06261e5-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '9748d5c0ef86afae-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '9d4097088fc2a0e2-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'af7b87f5134559ad-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'b0b776678c9c2b0e-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'b4871f96124a0d16-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'd14920f5b02075a7-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'e70021f467623b89-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    'f1168515f59b0dea-ps' = 'frame-confirmed material/GBuffer producer; six MRT outputs; not light evaluation'
    '02505845d94953e3-ps' = 'frame-confirmed forward/translucent/decal-style material draw; full material interpolants and depth target; not fullscreen light evaluation'
    '4f8473a854188417-ps' = 'frame-confirmed forward/translucent/decal-style material draw; full material interpolants and depth target; not fullscreen light evaluation'
    '5109645fe95f2d33-ps' = 'frame-confirmed forward/translucent/decal-style material draw; full material interpolants and depth target; not fullscreen light evaluation'
    'e4e9b8599f14f84a-ps' = 'frame-confirmed forward/translucent/decal-style material draw; full material interpolants and depth target; not fullscreen light evaluation'
    'e61f215a51927d71-ps' = 'frame-confirmed forward/translucent/decal-style material draw; full material interpolants and depth target; not fullscreen light evaluation'
    '50b5dd32b6683ccb-ps' = 'material/GBuffer permutation; six MRT outputs; not light evaluation'
    '6586f9a78da2d3c0-ps' = 'forward material permutation with full material interpolants and scene-depth output contract; not fullscreen light evaluation'
    'f1df6520877f6670-ps' = 'forward material permutation with full material interpolants and scene-depth output contract; not fullscreen light evaluation'
    '3cf3a91a7f55fb0d-ps' = 'layered volumetric slice pass; SV_RenderTargetArrayIndex input and single slice output'
    '8c9e92a0895efcdc-ps' = 'screen-space reflection variant; exact old Remake Helix header identifies screen-space reflections with a dithering exception and no full disable'
    '08bb8764f1840179-cs' = 'tiled-local-light-compute; isolation observation: hair/face'
    '0e97888f9a8767da-cs' = 'tiled-local-light-compute; isolation observation: hair'
    '5a9fbefe0ab6f815-cs' = 'tiled-local-light-compute; isolation observation: face/body'
    '62b33a2d1e505241-cs' = 'tiled-local-light-compute; broad/everything variant; accepted left-edge fade'
    'c30cdc8365df9840-cs' = 'tiled-local-light-compute; isolation observation: face'
    'f97a821dddaa328a-cs' = '16x16 tile material-class classifier and light-list selector'
    'b9e2305a994308f2-cs' = '8x8 tiled capsule-occlusion culling/evaluation producer; depth min/max reduction, capsule candidate list, analytical capsule-distance occlusion, and low-resolution occlusion/list outputs; upstream infrastructure, not per-light BRDF evaluation'
    '4b6fb3f0b78f9016-cs' = '120x68x96 volumetric media field synthesis from 3D noise inputs; precedes temporal and local-light volumetric injection'
    '8b1f6ebe443b5615-ps' = 'material/GBuffer producer observed on clothing; six MRT outputs; not proven light evaluation'
    'a77b589dce5822d6-ps' = 'verified full-resolution temporal SSAO'
    'b2bc6059f9a39c7f-ps' = 'verified screen-space reflection trace/resolve output'
    'aadc1c2374853914-ps' = 'directional/cascade shadow projection and filtering; reconstructs the receiver from scene depth and performs four offset gathers from a Texture2DArray shadow map; produces packed shadow factors'
    'e2aa1c8cb39e0a55-ps' = 'verified reflection-environment plus SSR composite'
    'c62607f2631cf47e-ps' = 'reflection-environment/indirect-lighting composition variant; shares the cache-unique shading-model BRDF signature and output scaling of verified e2aa1c8cb39e0a55; not a shadow pass'
    'c25d7f5229662b97-ps' = 'verified volumetric local-light injection'
    'cbc771ff8a37a0b3-ps' = 'verified temporal volumetric injection'
    'ef7fe8d9c4e9ad15-cs' = 'verified volumetric scattering/history'
    'af6cd28a0108a18a-ps' = 'verified UI-safe final scene-color post process'
    '41f1bf8b79d01319-ps' = 'verified final presentation/image adjustment'
}

$universal = Get-Content -Raw -LiteralPath $UniversalMatchReport | ConvertFrom-Json
$universalIdentitySet = @{}
foreach ($match in @($universal.matches)) {
    $universalIdentitySet["$($match.hash.ToLowerInvariant())-$($match.stage.ToLowerInvariant())"] = $true
}
$universalCandidates = @(
    foreach ($group in (@($universal.matches) | Group-Object hash, stage)) {
        $first = $group.Group[0]
        $identity = "$($first.hash.ToLowerInvariant())-$($first.stage.ToLowerInvariant())"
        [pscustomobject]@{
            hash = $first.hash.ToLowerInvariant()
            stage = $first.stage.ToLowerInvariant()
            families = @($group.Group.family | Sort-Object -Unique)
            rules = @($group.Group.section | Sort-Object -Unique)
            verifiedPasses = if ($verifiedByIdentity.ContainsKey($identity)) {
                @($verifiedByIdentity[$identity])
            } else {
                @()
            }
            observedRole = if ($observedRoles.ContainsKey($identity)) {
                $observedRoles[$identity]
            } else {
                $null
            }
            exactOldRemakeHelixHash = $helixByIdentity.ContainsKey($identity)
            status = if ($verifiedByIdentity.ContainsKey($identity) -or $observedRoles.ContainsKey($identity)) {
                'evidence-backed-role'
            } else {
                'candidate-only'
            }
        }
    }
)

$donorFingerprints = @(
    Get-ChildItem -LiteralPath $DonorDirectory -Recurse -File -Filter '*_Fingerprint.json' |
        ForEach-Object {
            $fingerprint = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
            $family = $fingerprint.name
            $version = $null
            if ($fingerprint.name -match '^GameVersion(?<version>1001_1000|1003_1002|1004|1005)_(?<family>.+)$') {
                $version = $Matches.version
                $family = $Matches.family
            }
            $target = @($fingerprint.targets)[0]
            $analysis = $target.shaderAnalysis
            [pscustomobject]@{
                family = $family
                version = $version
                stage = ($fingerprint.shaderProfile -split '_')[0]
                profile = $fingerprint.shaderProfile
                entryPoint = $analysis.entryFunctionName
                knownHashes = @($target.knownShaderBytecodeHashes)
                portableReflectionIdentityHash = $analysis.portableReflectionIdentityHash
                crossVersionIdentityHash = $analysis.crossVersionIdentityHash
                semanticInstructionSetHash = $analysis.semanticInstructionSetHash
                instructionCount = $analysis.instructionStatistics.instructionCount
                sourceFile = $fingerprint.sourceFile
                fingerprintFile = $_.FullName
                excludedFromCurrentPriority = $family -match '^(OceanA|WaterA|WaterB)$'
            }
        } |
        Sort-Object family, version
)

$configuration = Get-Content -Raw -LiteralPath (Join-Path $DonorDirectory 'ShaderConfigurations.json') | ConvertFrom-Json
$donorSettingGroups = @(
    foreach ($group in (@($configuration.properties) | Group-Object sourceFile | Sort-Object Name)) {
        [pscustomobject]@{
            sourceFile = $group.Name
            settingCount = $group.Count
            excludedFromCurrentPriority = $group.Name -match 'Water|Ocean'
            settings = @(
                $group.Group |
                    Select-Object name, type, defaultValue, value, range, comment |
                    Sort-Object name
            )
        }
    }
)

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    scope = [ordered]@{
        game = 'Final Fantasy VII Remake Intergrade'
        api = 'Direct3D 11'
        shaderModel = 'SM5'
        capturedAreaOnly = $true
        donorGame = 'Final Fantasy VII Rebirth'
        donorApi = 'Direct3D 12'
        donorShaderModel = 'SM6.6'
        donorIsBehavioralReferenceOnly = $true
        excludedDonorFamilies = @('OceanA', 'WaterA', 'WaterB')
    }
    inputs = [ordered]@{
        shaderCacheDirectory = (Resolve-Path -LiteralPath $ShaderCacheDirectory).Path
        helixReferenceDirectory = (Resolve-Path -LiteralPath $HelixReferenceDirectory).Path
        donorDirectory = (Resolve-Path -LiteralPath $DonorDirectory).Path
        universalMatchReport = (Resolve-Path -LiteralPath $UniversalMatchReport).Path
        shaderMap = (Resolve-Path -LiteralPath $ShaderMapPath).Path
    }
    remakeCapture = [ordered]@{
        shaderCount = $liveShaders.Count
        stageCounts = @(
            $liveShaders |
                Group-Object stage |
                Sort-Object Name |
                ForEach-Object { [pscustomobject]@{ stage = $_.Name; count = $_.Count } }
        )
        shaders = $liveShaders
    }
    exactOldRemakeHelixIntersection = [ordered]@{
        count = $exactHelixIntersection.Count
        stageCounts = @(
            $exactHelixIntersection |
                Group-Object stage |
                Sort-Object Name |
                ForEach-Object { [pscustomobject]@{ stage = $_.Name; count = $_.Count } }
        )
        shaders = $exactHelixIntersection
    }
    universalMatcher = [ordered]@{
        patternCount = $universal.patternSections.compiled
        compileFailureCount = $universal.patternSections.failed
        timeoutCount = @($universal.matchTimeouts).Count
        rawMatchCount = @($universal.matches).Count
        uniqueCandidateCount = $universalCandidates.Count
        candidates = $universalCandidates
    }
    verifiedRemakePasses = [ordered]@{
        passes = @(
            foreach ($pass in @($shaderMap.passes)) {
                [pscustomobject]@{
                    id = $pass.id
                    stage = $pass.stage
                    status = $pass.status
                    hashes = @($pass.hashes)
                    partnerShaders = @($pass.partnerShaders)
                    universalMatchPresent = @(
                        foreach ($hash in @($pass.hashes)) {
                            if (-not $hash) {
                                continue
                            }
                            $universalIdentitySet.ContainsKey("$($hash.ToLowerInvariant())-$($pass.stage.ToLowerInvariant())")
                        }
                    ) -contains $true
                }
            }
        )
        verifiedHashesAbsentFromStereoRuleMatches = @(
            foreach ($pass in @($shaderMap.passes)) {
                foreach ($hash in @($pass.hashes)) {
                    if (-not $hash) {
                        continue
                    }
                    $identity = "$($hash.ToLowerInvariant())-$($pass.stage.ToLowerInvariant())"
                    if (-not $universalIdentitySet.ContainsKey($identity)) {
                        [pscustomobject]@{
                            id = $pass.id
                            hash = $hash.ToLowerInvariant()
                            stage = $pass.stage.ToLowerInvariant()
                            status = $pass.status
                        }
                    }
                }
            }
        )
    }
    rebirthDonor = [ordered]@{
        packageCount = $donorFingerprints.Count
        activePriorityPackageCount = @($donorFingerprints | Where-Object { -not $_.excludedFromCurrentPriority }).Count
        packages = $donorFingerprints
        settingGroups = $donorSettingGroups
    }
    caveats = @(
        'The imported Universal ShaderRegex rules target 3D Vision correction; they are not a complete renderer-effect inventory.',
        'Absence from the Universal stereo-rule matches can mean automatic stereo was already correct, not that an effect shader was missed.',
        'A Universal ShaderRegex match is structural family evidence, not semantic proof of the shader effect.',
        '3DMigoto can apply structural ShaderRegex rules to shaders first seen in later areas and cache the patched result; exhaustive hash collection is not required.',
        'Exact hashes prove bytecode identity only for the named shader and stage.',
        'The current Remake cache is regional and expands as new areas and permutations compile.',
        'Rebirth is a different game, renderer branch, API, and shader model; donor hashes and bindings are not portable.',
        'Effect concepts are portable, while stage, resources, registers, insertion points, and permutations require an adapter.'
    )
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$jsonPath = Join-Path $OutputDirectory 'coverage-audit.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$liveShaders | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'remake-current-area-shaders.csv') -NoTypeInformation -Encoding UTF8
$exactHelixIntersection | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'exact-old-remake-helix-intersection.csv') -NoTypeInformation -Encoding UTF8
$universalCandidates |
    Select-Object hash, stage, status, observedRole, exactOldRemakeHelixHash,
        @{ Name = 'families'; Expression = { $_.families -join ';' } },
        @{ Name = 'rules'; Expression = { $_.rules -join ';' } },
        @{ Name = 'verifiedPasses'; Expression = { $_.verifiedPasses -join ';' } } |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'universal-candidates.csv') -NoTypeInformation -Encoding UTF8
$donorFingerprints |
    Select-Object family, version, stage, profile, entryPoint,
        @{ Name = 'knownHashes'; Expression = { $_.knownHashes -join ';' } },
        portableReflectionIdentityHash, crossVersionIdentityHash, semanticInstructionSetHash,
        instructionCount, sourceFile, excludedFromCurrentPriority |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'rebirth-donor-packages.csv') -NoTypeInformation -Encoding UTF8

Write-Output "Coverage audit: $jsonPath"
Write-Output "Remake current-area shaders: $($liveShaders.Count)"
Write-Output "Exact old-Remake Helix intersections: $($exactHelixIntersection.Count)"
Write-Output "Universal raw matches: $(@($universal.matches).Count)"
Write-Output "Universal unique candidates: $($universalCandidates.Count)"
Write-Output "Rebirth donor packages: $($donorFingerprints.Count)"
Write-Output "Rebirth donor packages in current priority: $(@($donorFingerprints | Where-Object { -not $_.excludedFromCurrentPriority }).Count)"
