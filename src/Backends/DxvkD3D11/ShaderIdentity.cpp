#include "ShaderIdentity.h"

#include <array>
#include <iomanip>
#include <sstream>

namespace universal_shader::dxvk_d3d11 {

namespace {

constexpr std::uint64_t kFnv64Prime = 0x100000001b3ULL;

}  // namespace

std::string_view ShaderStageSuffix(ShaderStage stage) noexcept {
  switch (stage) {
    case ShaderStage::Vertex:   return "vs";
    case ShaderStage::Hull:     return "hs";
    case ShaderStage::Domain:   return "ds";
    case ShaderStage::Geometry: return "gs";
    case ShaderStage::Pixel:    return "ps";
    case ShaderStage::Compute:  return "cs";
  }

  return {};
}

std::optional<ShaderStage> ParseShaderStage(std::string_view suffix) noexcept {
  constexpr std::array<std::pair<std::string_view, ShaderStage>, 6> kStages = {{
      {"vs", ShaderStage::Vertex},
      {"hs", ShaderStage::Hull},
      {"ds", ShaderStage::Domain},
      {"gs", ShaderStage::Geometry},
      {"ps", ShaderStage::Pixel},
      {"cs", ShaderStage::Compute},
  }};

  for (const auto& entry : kStages) {
    if (suffix == entry.first)
      return entry.second;
  }

  return std::nullopt;
}

std::uint64_t MigotoFnv1(const void* bytecode, std::size_t bytecodeLength) noexcept {
  std::uint64_t hash = 0;
  const auto* bytes = static_cast<const std::uint8_t*>(bytecode);

  if (!bytes)
    return 0;

  for (std::size_t i = 0; i < bytecodeLength; ++i) {
    hash *= kFnv64Prime;
    hash ^= bytes[i];
  }

  return hash;
}

std::string FormatMigotoHash(std::uint64_t hash) {
  std::ostringstream stream;
  stream << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(16) << hash;
  return stream.str();
}

ShaderIdentity ShaderIdentity::FromOriginalBytecode(
    ShaderStage shaderStage,
    const void* bytecode,
    std::size_t bytecodeLength) noexcept {
  return ShaderIdentity{MigotoFnv1(bytecode, bytecodeLength), shaderStage};
}

std::string ShaderIdentity::hashString() const {
  return FormatMigotoHash(originalHash);
}

std::string ShaderIdentity::canonicalName() const {
  return hashString() + "-" + std::string(ShaderStageSuffix(stage));
}

}  // namespace universal_shader::dxvk_d3d11
