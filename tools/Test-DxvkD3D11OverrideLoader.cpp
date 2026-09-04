#include "d3d11/d3d11_shader_override.h"
#include "util/log/log.h"

#include <array>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;

namespace dxvk {

  void Logger::warn(const std::string&) { }

}

namespace {

  int fail(const std::string& message) {
    std::cerr << "FAIL: " << message << '\n';
    return 1;
  }


  bool writePattern(const fs::path& path, std::size_t size, std::uint8_t value) {
    std::vector<std::uint8_t> bytes(size, value);
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(bytes.data()),
      static_cast<std::streamsize>(bytes.size()));
    return stream.good();
  }


  bool matches(
    const dxvk::D3D11ShaderOverrideSource& source,
          std::size_t                     size,
          std::uint8_t                    value) {
    if (!source || source.replacement->size() != size)
      return false;

    for (const auto byte : *source.replacement) {
      if (byte != value)
        return false;
    }

    return true;
  }

}


int main(int argc, char** argv) {
  if (argc != 2)
    return fail("expected a temporary replacement directory");

  const fs::path root = argv[1];
  fs::create_directories(root);

  const std::array<std::uint8_t, 4> original = { 'D', 'X', 'B', 'C' };
  dxvk::D3D11ShaderOverride loader(root.string());
  auto missing = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());

  if (missing || missing.path.empty())
    return fail("missing replacement did not fail closed with a canonical path");

  if (!writePattern(missing.path, 4096u, 0x2au))
    return fail("could not create the first replacement fixture");

  auto first = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());
  if (!matches(first, 4096u, 0x2au))
    return fail("first replacement snapshot was not loaded");

  auto cached = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());
  if (!matches(cached, 4096u, 0x2au) || cached.replacement.get() != first.replacement.get())
    return fail("unchanged replacement did not reuse the cached immutable snapshot");

  std::atomic<bool> concurrentFailure = false;
  std::vector<std::thread> workers;

  for (std::size_t worker = 0u; worker < 16u; worker++) {
    workers.emplace_back([&] {
      for (std::size_t iteration = 0u; iteration < 128u; iteration++) {
        auto source = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());

        if (!matches(source, 4096u, 0x2au)
         || source.replacement.get() != first.replacement.get()) {
          concurrentFailure.store(true, std::memory_order_relaxed);
          return;
        }
      }
    });
  }

  for (auto& worker : workers)
    worker.join();

  if (concurrentFailure.load(std::memory_order_relaxed))
    return fail("concurrent resolves did not return one stable cached snapshot");

  if (!writePattern(missing.path, 8192u, 0x6bu))
    return fail("could not replace the fixture with new content");

  auto refreshed = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());
  if (!matches(refreshed, 8192u, 0x6bu)
   || refreshed.replacement.get() == first.replacement.get())
    return fail("replacement metadata change did not refresh the cached snapshot");

  std::error_code error;
  fs::remove(missing.path, error);
  if (error)
    return fail("could not remove the replacement fixture");

  if (loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size()))
    return fail("deleted replacement remained active from cache");

  if (!writePattern(missing.path, 1024u, 0x91u))
    return fail("could not recreate the replacement fixture");

  auto recreated = loader.resolve(VK_SHADER_STAGE_FRAGMENT_BIT, original.data(), original.size());
  if (!matches(recreated, 1024u, 0x91u))
    return fail("recreated replacement was not admitted after cache invalidation");

  std::cout << "PASS: bounded DXVK replacement cache is concurrent, refreshable, and fail-closed\n";
  return 0;
}
