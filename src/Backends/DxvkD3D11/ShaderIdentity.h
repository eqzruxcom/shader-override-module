#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace universal_shader::dxvk_d3d11 {

enum class ShaderStage : std::uint8_t {
  Vertex,
  Hull,
  Domain,
  Geometry,
  Pixel,
  Compute,
};

std::string_view ShaderStageSuffix(ShaderStage stage) noexcept;
std::optional<ShaderStage> ParseShaderStage(std::string_view suffix) noexcept;

// Exact compatibility hash used by 3Dmigoto when shader_hash=3dmigoto:
// unseeded 64-bit FNV-1 over the original D3D shader bytecode.
std::uint64_t MigotoFnv1(const void* bytecode, std::size_t bytecodeLength) noexcept;

std::string FormatMigotoHash(std::uint64_t hash);

struct ShaderIdentity {
  std::uint64_t originalHash = 0;
  ShaderStage stage = ShaderStage::Pixel;

  static ShaderIdentity FromOriginalBytecode(
      ShaderStage stage,
      const void* bytecode,
      std::size_t bytecodeLength) noexcept;

  std::string hashString() const;
  std::string canonicalName() const;
};

}  // namespace universal_shader::dxvk_d3d11
