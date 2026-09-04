#include "ShaderIdentity.h"
#include "ShaderReplacementResolver.h"

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using namespace universal_shader::dxvk_d3d11;

namespace {

std::vector<std::uint8_t> ReadAll(const fs::path& path) {
  std::ifstream stream(path, std::ios::binary);
  return std::vector<std::uint8_t>(
      std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

bool IsDxbc(const std::vector<std::uint8_t>& bytes) {
  return bytes.size() >= 4 && bytes[0] == 'D' && bytes[1] == 'X' &&
      bytes[2] == 'B' && bytes[3] == 'C';
}

bool WriteBytes(const fs::path& path, std::string_view bytes) {
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  return stream.good();
}

int Fail(const std::string& message) {
  std::cerr << "FAIL: " << message << '\n';
  return 1;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 11)
    return Fail("expected three fixture triples plus a temporary directory");

  const std::array<std::string_view, 6> suffixes = {"vs", "hs", "ds", "gs", "ps", "cs"};
  for (const auto suffix : suffixes) {
    const auto stage = ParseShaderStage(suffix);
    if (!stage || ShaderStageSuffix(*stage) != suffix)
      return Fail("shader-stage suffix round trip failed for " + std::string(suffix));
  }

  if (ParseShaderStage("rt"))
    return Fail("unsupported ray-tracing stage was accepted by the DX11 backend");

  for (int i = 1; i <= 9; i += 3) {
    const fs::path fixture = argv[i];
    const auto stage = ParseShaderStage(argv[i + 1]);
    const std::string expected = argv[i + 2];

    if (!stage)
      return Fail("unknown fixture stage " + std::string(argv[i + 1]));

    const auto bytes = ReadAll(fixture);
    if (!IsDxbc(bytes))
      return Fail("fixture is not a DXBC container: " + fixture.string());

    const auto identity = ShaderIdentity::FromOriginalBytecode(*stage, bytes.data(), bytes.size());
    if (identity.hashString() != expected)
      return Fail("hash mismatch for " + fixture.string() + ": expected " + expected +
          ", got " + identity.hashString());

    if (identity.canonicalName() != expected + "-" + std::string(argv[i + 1]))
      return Fail("canonical name mismatch for " + fixture.string());

    std::cout << "PASS: " << identity.canonicalName() << " <- " << fixture.string() << '\n';
  }

  const fs::path replacementRoot = argv[10];
  fs::create_directories(replacementRoot);

  const std::array<std::uint8_t, 4> original = {'D', 'X', 'B', 'C'};
  const auto identity = ShaderIdentity::FromOriginalBytecode(
      ShaderStage::Pixel, original.data(), original.size());
  const ShaderReplacementResolver resolver(replacementRoot);

  const auto hlslPath = replacementRoot / (identity.canonicalName() + "_replace.hlsl");
  const auto dxbcPath = replacementRoot / (identity.canonicalName() + "_replace.bin");
  const auto originalDumpPath = replacementRoot / (identity.canonicalName() + ".bin");

  if (!WriteBytes(originalDumpPath, "captured original"))
    return Fail("could not create original-dump collision test");
  if (resolver.resolve(identity))
    return Fail("resolver treated a captured <hash>-<stage>.bin as a replacement");

  if (!WriteBytes(hlslPath, "float4 main() : SV_Target { return 0; }"))
    return Fail("could not create HLSL resolver fixture");
  auto candidate = resolver.resolve(identity);
  if (!candidate || candidate->path != hlslPath || candidate->format != ReplacementFormat::Hlsl)
    return Fail("HLSL replacement resolution failed");

  if (!WriteBytes(dxbcPath, "compiled replacement"))
    return Fail("could not create DXBC resolver fixture");
  candidate = resolver.resolve(identity);
  if (!candidate || candidate->path != dxbcPath || candidate->format != ReplacementFormat::Dxbc)
    return Fail("compiled DXBC did not take priority over HLSL");

  std::cout << "PASS: resolver preserves original identity and 3Dmigoto-compatible replacement priority\n";
  return 0;
}
