[CmdletBinding()]
param(
    [string]$ForkRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\3DmigotoFork')
)

$ErrorActionPreference = 'Stop'

function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Replace-Once([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Missing source anchor: $Label" }
    if ($Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Source anchor is not unique: $Label"
    }
    $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

$fork = [IO.Path]::GetFullPath($ForkRoot)
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $fork.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Fork must stay inside project root: $fork"
}

$dx11 = Join-Path $fork 'DirectX11'
$regexSource = Join-Path $dx11 'ShaderRegex.cpp.upstream'
$iniSource = Join-Path $dx11 'IniHandler.cpp.upstream'
$regexTarget = Join-Path $dx11 'ShaderRegex.cpp'
$iniTarget = Join-Path $dx11 'IniHandler.cpp'
$projectTarget = Join-Path $dx11 'DirectX11.vcxproj'
$projectSource = $projectTarget + '.upstream'

$expected = [ordered]@{
    $regexSource = 'A245293CE42077865C040EC070EA0A3EF8ACB096D30E9275F28A32746C23F2C1'
    $iniSource = '665EB3C23B48EE90052E7E5D2812FB5F75C47B01B9CE1C4B57CEBF23355A3284'
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Missing baseline: $($entry.Key)" }
    if ((Get-Hash $entry.Key) -ne $entry.Value) { throw "Baseline drift: $($entry.Key)" }
}

if (-not (Test-Path -LiteralPath $projectSource -PathType Leaf)) {
    Copy-Item -LiteralPath $projectTarget -Destination $projectSource
}

$regex = [IO.File]::ReadAllText($regexSource)
$regex = Replace-Once $regex '#include "ShaderRegex.h"' "#include `"ShaderRegex.h`"`r`n#include `"ShaderFamily.h`"" 'ShaderRegex family include'
$regex = Replace-Once $regex '#define SHADER_REGEX_CACHE_VERSION 1' '#define SHADER_REGEX_CACHE_VERSION 2' 'ShaderRegex cache version'
$regex = Replace-Once $regex "`t`tgroup->apply_regex_patterns(asm_text, &match, &patch);" "`t`tApplyShaderRegexWithFamilyGate(group, asm_text, shader_model, hash, &match, &patch);" 'family-gated regex application'

$ini = [IO.File]::ReadAllText($iniSource)
$ini = Replace-Once $ini '#include "ShaderRegex.h"' "#include `"ShaderRegex.h`"`r`n#include `"ShaderFamily.h`"" 'IniHandler family include'
$ini = Replace-Once $ini @'
	L"filter_index",
	// L"type" =asm/hlsl? I'd rather not encourage autofixes on HLSL
'@ @'
	L"filter_index",
	L"family_mode",
	L"approved_hashes",
	L"required_bindings",
	L"forbidden_bindings",
	L"min_instructions",
	L"max_instructions",
	// L"type" =asm/hlsl? I'd rather not encourage autofixes on HLSL
'@ 'family INI keys'
$ini = Replace-Once $ini @'
	if (GetIniStringAndLog(section_id->c_str(), L"temps", NULL, &setting))
		regex_group->temp_regs = vec_to_set(split_string(&setting, ' '));

	regex_group->ini_section = *section_id;
'@ @'
	if (GetIniStringAndLog(section_id->c_str(), L"temps", NULL, &setting))
		regex_group->temp_regs = vec_to_set(split_string(&setting, ' '));

	if (!ParseShaderFamilyConfiguration(section_id, regex_group))
		return false;

	regex_group->ini_section = *section_id;
'@ 'family main-section parser'
$ini = Replace-Once $ini @'
		i->second.command_list.clear();
		i->second.post_command_list.clear();
'@ @'
		RemoveShaderFamilyConfiguration(&i->second);
		i->second.command_list.clear();
		i->second.post_command_list.clear();
'@ 'family cleanup'
$ini = Replace-Once $ini @'
	shader_regex_group_index.clear();
	shader_regex_groups.clear();
'@ @'
	shader_regex_group_index.clear();
	ClearShaderFamilyConfigurations();
	shader_regex_groups.clear();
'@ 'family reload reset'
$ini = Replace-Once $ini @'
	// When we load ShaderRegex metadata from the cache we need to look up
'@ @'
	// Reject incomplete family definitions before cache indexing. This is
	// fail-closed: an invalid family cannot patch a single shader.
	for (j = shader_regex_groups.begin(); j != shader_regex_groups.end(); ) {
		auto current = j++;
		std::wstring reason;
		if (!ShaderFamilyConfigurationIsComplete(&current->second, &reason)) {
			IniWarning("WARNING: disabling incomplete shader family [%S]: %S\n",
				current->first.c_str(), reason.c_str());
			std::wstring id = current->first;
			delete_regex_group(&id);
		}
	}

	// When we load ShaderRegex metadata from the cache we need to look up
'@ 'family completeness gate'

$project = [IO.File]::ReadAllText($projectSource)
$project = Replace-Once $project @'
    <ClCompile Include="ShaderRegex.cpp" />
'@ @'
    <ClCompile Include="ShaderRegex.cpp" />
    <ClCompile Include="ShaderFamily.cpp">
      <ForcedIncludeFiles>ShaderFamilyCompileFix.h;%(ForcedIncludeFiles)</ForcedIncludeFiles>
    </ClCompile>
'@ 'family source project entry'
$project = Replace-Once $project @'
    <ClInclude Include="ShaderRegex.h" />
'@ @'
    <ClInclude Include="ShaderRegex.h" />
    <ClInclude Include="ShaderFamily.h" />
    <ClInclude Include="ShaderFamilyCompileFix.h" />
'@ 'family header project entries'

[IO.File]::WriteAllText($regexTarget, $regex, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($iniTarget, $ini, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($projectTarget, $project, [Text.UTF8Encoding]::new($false))

$manifest = [ordered]@{
    schemaVersion = 1
    upstreamCommit = '8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    feature = 'fail-closed-shader-family-gates'
    files = @(
        foreach ($path in @($regexTarget, $iniTarget, $projectTarget, (Join-Path $dx11 'ShaderFamily.cpp'), (Join-Path $dx11 'ShaderFamily.h'))) {
            [ordered]@{ path = $path.Substring($projectRoot.Length + 1).Replace('\','/'); sha256 = (Get-Hash $path) }
        }
    )
}
$manifestPath = Join-Path $fork 'shader-family-engine-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host "PASS: generated 3Dmigoto shader-family engine fork"
Write-Host $manifestPath

