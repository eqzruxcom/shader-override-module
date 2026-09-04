#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

std::vector<std::uint8_t> readFile(const wchar_t* path) {
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream)
    throw std::runtime_error("Could not open shader bytecode");
  const auto end = stream.tellg();
  if (end <= 0 || static_cast<std::uint64_t>(end) > std::numeric_limits<std::size_t>::max())
    throw std::runtime_error("Shader bytecode has an invalid size");
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(end));
  stream.seekg(0, std::ios::beg);
  stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  if (!stream)
    throw std::runtime_error("Could not read complete shader bytecode");
  return bytes;
}

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    std::cerr << operation << " failed with HRESULT 0x" << std::hex
              << static_cast<unsigned long>(result) << std::dec << "\n";
    throw std::runtime_error(operation);
  }
}

std::wstring modulePath(const wchar_t* name) {
  const HMODULE module = GetModuleHandleW(name);
  if (!module)
    return L"<not loaded>";
  std::vector<wchar_t> path(32768u, L'\0');
  const DWORD length = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size())
    return L"<unavailable>";
  return std::wstring(path.data(), length);
}

} // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) {
    std::wcerr << L"Usage: DxvkD3D11CreateShader.exe <compute-dxbc>\n";
    return 64;
  }
  try {
    const auto bytecode = readFile(argv[1]);
    const D3D_FEATURE_LEVEL requested = D3D_FEATURE_LEVEL_11_0;
    D3D_FEATURE_LEVEL created = D3D_FEATURE_LEVEL_9_1;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    check(D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_SINGLETHREADED,
      &requested, 1u, D3D11_SDK_VERSION, &device, &created, &context),
      "D3D11CreateDevice");

    ComPtr<ID3D11ComputeShader> shader;
    check(device->CreateComputeShader(bytecode.data(), bytecode.size(), nullptr, &shader),
      "ID3D11Device::CreateComputeShader");

    std::wcout << L"D3D11Module: " << modulePath(L"d3d11.dll") << L"\n";
    std::wcout << L"DXGIModule: " << modulePath(L"dxgi.dll") << L"\n";
    std::cout << "FeatureLevel: 0x" << std::hex << static_cast<unsigned int>(created)
              << std::dec << "\n";
    std::cout << "BytecodeSize: " << bytecode.size() << "\n";
    std::cout << "PASS: compute shader object created\n";
    return 0;
  }
  catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << "\n";
    return 1;
  }
}
