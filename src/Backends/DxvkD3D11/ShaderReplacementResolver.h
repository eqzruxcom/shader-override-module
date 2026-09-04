#pragma once

#include "ShaderIdentity.h"

#include <filesystem>
#include <optional>

namespace universal_shader::dxvk_d3d11 {

enum class ReplacementFormat : std::uint8_t {
  Dxbc,
  Hlsl,
};

struct ReplacementCandidate {
  std::filesystem::path path;
  ReplacementFormat format = ReplacementFormat::Dxbc;
};

class ShaderReplacementResolver {
 public:
  explicit ShaderReplacementResolver(std::filesystem::path root);

  const std::filesystem::path& root() const noexcept;
  std::optional<ReplacementCandidate> resolve(const ShaderIdentity& identity) const;

 private:
  std::filesystem::path root_;
};

}  // namespace universal_shader::dxvk_d3d11
