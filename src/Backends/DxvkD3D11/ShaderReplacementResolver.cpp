#include "ShaderReplacementResolver.h"

#include <array>
#include <system_error>

namespace universal_shader::dxvk_d3d11 {

ShaderReplacementResolver::ShaderReplacementResolver(std::filesystem::path root)
    : root_(std::move(root)) {}

const std::filesystem::path& ShaderReplacementResolver::root() const noexcept {
  return root_;
}

std::optional<ReplacementCandidate> ShaderReplacementResolver::resolve(
    const ShaderIdentity& identity) const {
  struct Suffix {
    const char* text;
    ReplacementFormat format;
  };

  // Compiled DXBC wins. The names deliberately mirror 3Dmigoto and never
  // accept <hash>-<stage>.bin, because that name is also used for originals.
  constexpr std::array<Suffix, 3> kPriority = {{
      {"_replace.bin", ReplacementFormat::Dxbc},
      {"_replace.hlsl", ReplacementFormat::Hlsl},
      {"_replace.txt", ReplacementFormat::Hlsl},
  }};

  const std::string base = identity.canonicalName();

  for (const auto& suffix : kPriority) {
    const auto candidate = root_ / (base + suffix.text);
    std::error_code error;

    if (!std::filesystem::is_regular_file(candidate, error) || error)
      continue;

    const auto size = std::filesystem::file_size(candidate, error);
    if (error || size == 0)
      continue;

    return ReplacementCandidate{candidate, suffix.format};
  }

  return std::nullopt;
}

}  // namespace universal_shader::dxvk_d3d11
