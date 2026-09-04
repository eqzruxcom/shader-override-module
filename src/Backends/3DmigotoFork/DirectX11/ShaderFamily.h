#pragma once

#include <string>

class ShaderRegexGroup;

// Engine-level safety and promotion gates layered over ShaderRegex. Legacy
// groups retain their exact behavior unless family_mode is explicitly set.
void ClearShaderFamilyConfigurations();
bool ParseShaderFamilyConfiguration(const std::wstring *section_id, ShaderRegexGroup *group);
void RemoveShaderFamilyConfiguration(ShaderRegexGroup *group);
bool ShaderFamilyConfigurationIsComplete(ShaderRegexGroup *group, std::wstring *reason);

// Evaluates structural patterns on a disposable copy for gated families.
// Rejected/audit candidates cannot mutate live assembly or link command lists.
void ApplyShaderRegexWithFamilyGate(
	ShaderRegexGroup *group,
	std::string *asm_text,
	const std::string *shader_model,
	unsigned long long shader_hash,
	bool *match,
	bool *patch);

