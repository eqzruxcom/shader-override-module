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
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

std::vector<std::uint8_t> readFile(const wchar_t* path) {
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream)
    throw std::runtime_error("Could not open shader bytecode");

  const auto end = stream.tellg();
  if (end <= 0)
    throw std::runtime_error("Shader bytecode is empty");
  if (static_cast<std::uint64_t>(end) > std::numeric_limits<std::size_t>::max())
    throw std::runtime_error("Shader bytecode is too large");

  std::vector<std::uint8_t> data(static_cast<std::size_t>(end));
  stream.seekg(0, std::ios::beg);
  stream.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(data.size()));
  if (!stream)
    throw std::runtime_error("Could not read complete shader bytecode");
  return data;
}

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    std::cerr << operation << " failed with HRESULT 0x" << std::hex
              << static_cast<unsigned long>(result) << std::dec << "\n";
    throw std::runtime_error(operation);
  }
}

std::wstring adapterName(ID3D11Device* device) {
  ComPtr<IDXGIDevice> dxgiDevice;
  check(device->QueryInterface(IID_PPV_ARGS(&dxgiDevice)), "QueryInterface(IDXGIDevice)");

  ComPtr<IDXGIAdapter> adapter;
  check(dxgiDevice->GetAdapter(&adapter), "IDXGIDevice::GetAdapter");

  DXGI_ADAPTER_DESC description = {};
  check(adapter->GetDesc(&description), "IDXGIAdapter::GetDesc");
  return description.Description;
}

std::wstring modulePath(const wchar_t* moduleName) {
  const HMODULE module = GetModuleHandleW(moduleName);
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
  if (argc != 3) {
    std::wcerr << L"Usage: DxvkD3D11Smoke.exe <original-dxbc> <expected-uint>\n";
    return 64;
  }

  try {
    wchar_t* parseEnd = nullptr;
    const unsigned long parsedExpected = std::wcstoul(argv[2], &parseEnd, 10);
    if (!parseEnd || *parseEnd != L'\0' || parsedExpected > std::numeric_limits<std::uint32_t>::max()) {
      std::wcerr << L"Invalid expected value: " << argv[2] << L"\n";
      return 64;
    }
    const auto expected = static_cast<std::uint32_t>(parsedExpected);
    const auto shaderBytecode = readFile(argv[1]);

    const D3D_FEATURE_LEVEL requestedLevel = D3D_FEATURE_LEVEL_11_0;
    D3D_FEATURE_LEVEL createdLevel = D3D_FEATURE_LEVEL_9_1;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    check(D3D11CreateDevice(
      nullptr,
      D3D_DRIVER_TYPE_HARDWARE,
      nullptr,
      D3D11_CREATE_DEVICE_SINGLETHREADED,
      &requestedLevel,
      1u,
      D3D11_SDK_VERSION,
      &device,
      &createdLevel,
      &context), "D3D11CreateDevice");

    ComPtr<ID3D11ComputeShader> shader;
    check(device->CreateComputeShader(
      shaderBytecode.data(), shaderBytecode.size(), nullptr, &shader),
      "ID3D11Device::CreateComputeShader");

    const std::uint32_t initial = 0u;
    D3D11_SUBRESOURCE_DATA initialData = {};
    initialData.pSysMem = &initial;

    D3D11_BUFFER_DESC outputDescription = {};
    outputDescription.ByteWidth = sizeof(std::uint32_t);
    outputDescription.Usage = D3D11_USAGE_DEFAULT;
    outputDescription.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    outputDescription.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    outputDescription.StructureByteStride = sizeof(std::uint32_t);

    ComPtr<ID3D11Buffer> output;
    check(device->CreateBuffer(&outputDescription, &initialData, &output),
      "ID3D11Device::CreateBuffer(output)");

    D3D11_UNORDERED_ACCESS_VIEW_DESC viewDescription = {};
    viewDescription.Format = DXGI_FORMAT_UNKNOWN;
    viewDescription.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    viewDescription.Buffer.NumElements = 1u;

    ComPtr<ID3D11UnorderedAccessView> outputView;
    check(device->CreateUnorderedAccessView(output.Get(), &viewDescription, &outputView),
      "ID3D11Device::CreateUnorderedAccessView");

    D3D11_BUFFER_DESC readbackDescription = outputDescription;
    readbackDescription.Usage = D3D11_USAGE_STAGING;
    readbackDescription.BindFlags = 0u;
    readbackDescription.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    readbackDescription.MiscFlags = 0u;

    ComPtr<ID3D11Buffer> readback;
    check(device->CreateBuffer(&readbackDescription, nullptr, &readback),
      "ID3D11Device::CreateBuffer(readback)");

    ID3D11UnorderedAccessView* views[] = { outputView.Get() };
    context->CSSetShader(shader.Get(), nullptr, 0u);
    context->CSSetUnorderedAccessViews(0u, 1u, views, nullptr);
    context->Dispatch(1u, 1u, 1u);

    ID3D11UnorderedAccessView* nullViews[] = { nullptr };
    context->CSSetUnorderedAccessViews(0u, 1u, nullViews, nullptr);
    context->CopyResource(readback.Get(), output.Get());

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    check(context->Map(readback.Get(), 0u, D3D11_MAP_READ, 0u, &mapped),
      "ID3D11DeviceContext::Map");
    const auto actual = *static_cast<const std::uint32_t*>(mapped.pData);
    context->Unmap(readback.Get(), 0u);

    std::wcout << L"Adapter: " << adapterName(device.Get()) << L"\n";
    std::wcout << L"D3D11Module: " << modulePath(L"d3d11.dll") << L"\n";
    std::wcout << L"DXGIModule: " << modulePath(L"dxgi.dll") << L"\n";
    std::cout << "FeatureLevel: 0x" << std::hex << static_cast<unsigned int>(createdLevel)
              << std::dec << "\n";
    std::cout << "Result: " << actual << "\n";
    std::cout << "Expected: " << expected << "\n";

    if (actual != expected) {
      std::cerr << "FAIL: compute result mismatch\n";
      return 2;
    }

    std::cout << "PASS: D3D11 compute result matched\n";
    return 0;
  }
  catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << "\n";
    return 1;
  }
}
