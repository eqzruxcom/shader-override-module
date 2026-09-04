#include "ShaderFamily.h"

#include "IniHandler.h"
#include "ShaderRegex.h"
#include "Overlay.h"
#include "log.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <utility>
#include <vector>

namespace {

enum class FamilyMode {
	Legacy,
	Audit,
	Approved,
	Automatic
};

struct FamilyConfiguration {
	FamilyMode mode = FamilyMode::Legacy;
	std::set<unsigned long long> approved_hashes;
	std::set<std::string> required_bindings;
	std::set<std::string> forbidden_bindings;
	unsigned min_instructions = 0;
	unsigned max_instructions = 0;
	bool instruction_range_set = false;
};

std::map<ShaderRegexGroup*, FamilyConfiguration> family_configurations;

bool get_ini_string_and_log(
	const wchar_t *section,
	const wchar_t *key,
	std::string *value)
{
	const bool found = GetIniString(section, key, nullptr, value);
	if (found)
		LogInfo("  %S=%s\n", key, value->c_str());
	return found;
}

std::string lower_ascii(std::string value)
{
	std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
		return static_cast<char>(std::tolower(c));
	});
	return value;
}

std::vector<std::string> split_words(std::string value)
{
	std::replace(value.begin(), value.end(), ',', ' ');
	std::replace(value.begin(), value.end(), ';', ' ');

	std::istringstream stream(value);
	std::vector<std::string> words;
	std::string word;
	while (stream >> word)
		words.push_back(word);
	return words;
}

bool token_character(char c)
{
	return std::isalnum(static_cast<unsigned char>(c)) || c == '_';
}

bool line_contains_token(const std::string &line, const std::string &token)
{
	size_t pos = 0;
	while ((pos = line.find(token, pos)) != std::string::npos) {
		const size_t end = pos + token.size();
		const bool left_ok = pos == 0 || !token_character(line[pos - 1]);
		const bool right_ok = end == line.size() || !token_character(line[end]);
		if (left_ok && right_ok)
			return true;
		pos = end;
	}
	return false;
}

std::string normalise_binding(std::string binding)
{
	binding = lower_ascii(binding);
	// HLSL calls a constant-buffer register b0; DXBC assembly calls it cb0.
	if (binding.size() > 1 && binding[0] == 'b' &&
	    std::isdigit(static_cast<unsigned char>(binding[1])))
		binding.insert(binding.begin(), 'c');
	return binding;
}

bool declaration_has_binding(const std::string &assembly, const std::string &requested)
{
	std::istringstream stream(assembly);
	std::string line;
	const std::string binding = normalise_binding(requested);

	while (std::getline(stream, line)) {
		line = lower_ascii(line);
		const size_t first = line.find_first_not_of(" \t\r");
		if (first == std::string::npos || line.compare(first, 4, "dcl_") != 0)
			continue;
		if (line_contains_token(line, binding))
			return true;
	}
	return false;
}

unsigned instruction_count(const std::string &assembly)
{
	std::istringstream stream(assembly);
	std::string line;
	unsigned count = 0;

	while (std::getline(stream, line)) {
		const size_t first = line.find_first_not_of(" \t\r");
		if (first == std::string::npos || line.compare(first, 2, "//") == 0)
			continue;
		const std::string lowered = lower_ascii(line.substr(first));
		if (lowered.compare(0, 4, "dcl_") == 0 ||
		    lowered.compare(0, 12, "globalflags ") == 0 ||
		    lowered.find("_4_0") == 2 || lowered.find("_5_0") == 2)
			continue;
		if (count != (std::numeric_limits<unsigned>::max)())
			count++;
	}
	return count;
}

bool parse_mode(const std::string &text, FamilyMode *mode)
{
	const std::string value = lower_ascii(text);
	if (value == "legacy")
		*mode = FamilyMode::Legacy;
	else if (value == "audit")
		*mode = FamilyMode::Audit;
	else if (value == "approved")
		*mode = FamilyMode::Approved;
	else if (value == "automatic")
		*mode = FamilyMode::Automatic;
	else
		return false;
	return true;
}

bool parse_hashes(const std::string &text, std::set<unsigned long long> *hashes)
{
	for (const auto &word : split_words(text)) {
		char *end = nullptr;
		errno = 0;
		const unsigned long long value = _strtoui64(word.c_str(), &end, 16);
		if (errno || !end || *end || !value)
			return false;
		hashes->insert(value);
	}
	return true;
}

bool validate_contract(
	const FamilyConfiguration &config,
	const std::string &assembly,
	std::string *reason)
{
	for (const auto &binding : config.required_bindings) {
		if (!declaration_has_binding(assembly, binding)) {
			*reason = "missing required binding " + binding;
			return false;
		}
	}
	for (const auto &binding : config.forbidden_bindings) {
		if (declaration_has_binding(assembly, binding)) {
			*reason = "contains forbidden binding " + binding;
			return false;
		}
	}
	if (config.instruction_range_set) {
		const unsigned count = instruction_count(assembly);
		if (count < config.min_instructions || count > config.max_instructions) {
			*reason = "instruction count " + std::to_string(count) + " outside " +
				std::to_string(config.min_instructions) + ".." +
				std::to_string(config.max_instructions);
			return false;
		}
	}
	return true;
}

} // namespace

void ClearShaderFamilyConfigurations()
{
	family_configurations.clear();
}

bool ParseShaderFamilyConfiguration(const std::wstring *section_id, ShaderRegexGroup *group)
{
	std::string setting;
	FamilyConfiguration config;

	if (!get_ini_string_and_log(section_id->c_str(), L"family_mode", &setting))
		return true;

	if (!parse_mode(setting, &config.mode)) {
		LogOverlay(LOG_WARNING, "WARNING: [%S] invalid family_mode '%s'\n",
			section_id->c_str(), setting.c_str());
		return false;
	}

	if (get_ini_string_and_log(section_id->c_str(), L"approved_hashes", &setting) &&
	    !parse_hashes(setting, &config.approved_hashes)) {
		LogOverlay(LOG_WARNING, "WARNING: [%S] has invalid approved_hashes\n",
			section_id->c_str());
		return false;
	}
	if (get_ini_string_and_log(section_id->c_str(), L"required_bindings", &setting))
		for (const auto &word : split_words(setting))
			config.required_bindings.insert(normalise_binding(word));
	if (get_ini_string_and_log(section_id->c_str(), L"forbidden_bindings", &setting))
		for (const auto &word : split_words(setting))
			config.forbidden_bindings.insert(normalise_binding(word));

	bool min_found = false;
	bool max_found = false;
	const int minimum = GetIniInt(section_id->c_str(), L"min_instructions", -1, &min_found);
	const int maximum = GetIniInt(section_id->c_str(), L"max_instructions", -1, &max_found);
	if (min_found != max_found || (min_found && (minimum < 0 || maximum < 0))) {
		LogOverlay(LOG_WARNING,
			"WARNING: [%S] requires valid min_instructions and max_instructions\n",
			section_id->c_str());
		return false;
	}
	if (min_found) {
		config.min_instructions = static_cast<unsigned>(minimum);
		config.max_instructions = static_cast<unsigned>(maximum);
		config.instruction_range_set = true;
	}

	family_configurations[group] = std::move(config);
	return true;
}

void RemoveShaderFamilyConfiguration(ShaderRegexGroup *group)
{
	family_configurations.erase(group);
}

bool ShaderFamilyConfigurationIsComplete(ShaderRegexGroup *group, std::wstring *reason)
{
	const auto found = family_configurations.find(group);
	if (found == family_configurations.end() || found->second.mode == FamilyMode::Legacy)
		return true;

	const FamilyConfiguration &config = found->second;
	if (group->patterns.empty()) {
		*reason = L"family mode requires a structural Pattern";
		return false;
	}
	if (config.required_bindings.empty()) {
		*reason = L"family mode requires required_bindings";
		return false;
	}
	if (!config.instruction_range_set || config.min_instructions > config.max_instructions) {
		*reason = L"family mode requires a valid instruction range";
		return false;
	}
	if (config.mode == FamilyMode::Approved && config.approved_hashes.empty()) {
		*reason = L"approved mode requires approved_hashes";
		return false;
	}
	return true;
}

void ApplyShaderRegexWithFamilyGate(
	ShaderRegexGroup *group,
	std::string *asm_text,
	const std::string *shader_model,
	unsigned long long shader_hash,
	bool *match,
	bool *patch)
{
	const auto found = family_configurations.find(group);
	if (found == family_configurations.end() || found->second.mode == FamilyMode::Legacy) {
		group->apply_regex_patterns(asm_text, match, patch);
		return;
	}

	const FamilyConfiguration &config = found->second;
	std::string candidate = *asm_text;
	group->apply_regex_patterns(&candidate, match, patch);
	if (!*match)
		return;

	std::string reason;
	if (!validate_contract(config, *asm_text, &reason)) {
		LogInfo(
			"ShaderFamily: skipped %s %016I64x for [%S]: %s\n",
			shader_model->c_str(), shader_hash, group->ini_section.c_str(), reason.c_str());
		*match = false;
		*patch = false;
		return;
	}

	if (config.mode == FamilyMode::Audit ||
	    (config.mode == FamilyMode::Approved && !config.approved_hashes.count(shader_hash))) {
		const char *status = config.mode == FamilyMode::Audit
			? "audit mode"
			: "hash is not approved";
		LogOverlay(LOG_NOTICE,
			"ShaderFamily: candidate %s %016I64x for [%S] (%s)\n",
			shader_model->c_str(), shader_hash, group->ini_section.c_str(), status);
		*match = false;
		*patch = false;
		return;
	}

	// Only an approved or explicitly automatic family reaches live assembly.
	*asm_text = std::move(candidate);
}
