#include <d3d11shader.h>
#include <d3dcompiler.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

template <typename T>
class ComOwner {
 public:
  ComOwner() = default;
  ~ComOwner() { if (value_) value_->Release(); }
  ComOwner(const ComOwner&) = delete;
  ComOwner& operator=(const ComOwner&) = delete;
  T** put() { return &value_; }
  T* get() const { return value_; }

 private:
  T* value_ = nullptr;
};

std::vector<std::uint8_t> ReadFile(const char* path) {
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream)
    throw std::runtime_error(std::string("cannot open ") + path);
  const auto end = stream.tellg();
  if (end <= 0)
    throw std::runtime_error(std::string("empty shader file: ") + path);
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(end));
  stream.seekg(0, std::ios::beg);
  if (!stream.read(reinterpret_cast<char*>(bytes.data()), end))
    throw std::runtime_error(std::string("cannot read ") + path);
  return bytes;
}

std::string Safe(const char* value) {
  return value ? value : "";
}

std::string SignatureParameter(const D3D11_SIGNATURE_PARAMETER_DESC& d) {
  std::ostringstream s;
  s << Safe(d.SemanticName) << '|' << d.SemanticIndex << '|' << d.Register << '|'
    << d.SystemValueType << '|' << d.ComponentType << '|' << unsigned(d.Mask) << '|'
    << unsigned(d.ReadWriteMask) << '|' << d.Stream << '|' << d.MinPrecision;
  return s.str();
}

std::vector<std::string> ReadSignature(
    ID3D11ShaderReflection* reflection,
    UINT count,
    HRESULT (STDMETHODCALLTYPE ID3D11ShaderReflection::*getter)(UINT, D3D11_SIGNATURE_PARAMETER_DESC*)) {
  std::vector<std::string> result;
  result.reserve(count);
  for (UINT i = 0; i < count; ++i) {
    D3D11_SIGNATURE_PARAMETER_DESC desc = {};
    if (FAILED((reflection->*getter)(i, &desc)))
      throw std::runtime_error("cannot reflect shader signature");
    result.push_back(SignatureParameter(desc));
  }
  return result;
}

std::string TypeLayout(ID3D11ShaderReflectionType* type) {
  if (!type)
    throw std::runtime_error("missing reflected variable type");
  D3D11_SHADER_TYPE_DESC desc = {};
  if (FAILED(type->GetDesc(&desc)))
    throw std::runtime_error("cannot reflect variable type");

  std::ostringstream s;
  s << desc.Class << ':' << desc.Type << ':' << desc.Rows << ':' << desc.Columns << ':'
    << desc.Elements << ':' << desc.Members << ':' << desc.Offset << '[';
  for (UINT i = 0; i < desc.Members; ++i)
    s << TypeLayout(type->GetMemberTypeByIndex(i)) << ';';
  s << ']';
  return s.str();
}

std::vector<std::string> ConstantBufferLayouts(ID3D11ShaderReflection* reflection) {
  D3D11_SHADER_DESC shader = {};
  if (FAILED(reflection->GetDesc(&shader)))
    throw std::runtime_error("cannot reflect shader description");

  std::vector<std::string> result;
  for (UINT i = 0; i < shader.BoundResources; ++i) {
    D3D11_SHADER_INPUT_BIND_DESC binding = {};
    if (FAILED(reflection->GetResourceBindingDesc(i, &binding)))
      throw std::runtime_error("cannot reflect resource binding");
    if (binding.Type != D3D_SIT_CBUFFER && binding.Type != D3D_SIT_TBUFFER)
      continue;

    auto* buffer = reflection->GetConstantBufferByName(binding.Name);
    D3D11_SHADER_BUFFER_DESC bufferDesc = {};
    if (!buffer || FAILED(buffer->GetDesc(&bufferDesc)))
      throw std::runtime_error("cannot reflect constant buffer");

    std::vector<std::string> variables;
    for (UINT variableIndex = 0; variableIndex < bufferDesc.Variables; ++variableIndex) {
      auto* variable = buffer->GetVariableByIndex(variableIndex);
      D3D11_SHADER_VARIABLE_DESC variableDesc = {};
      if (!variable || FAILED(variable->GetDesc(&variableDesc)))
        throw std::runtime_error("cannot reflect constant-buffer variable");
      std::ostringstream variableLayout;
      variableLayout << variableDesc.StartOffset << ':' << variableDesc.Size << ':'
                     << variableDesc.uFlags << ':' << TypeLayout(variable->GetType());
      variables.push_back(variableLayout.str());
    }
    std::sort(variables.begin(), variables.end());

    std::ostringstream layout;
    layout << binding.BindPoint << ':' << binding.BindCount << ':' << binding.Type << ':'
           << bufferDesc.Type << ':' << bufferDesc.Size << ':' << bufferDesc.uFlags << '{';
    for (const auto& variable : variables)
      layout << variable << ';';
    layout << '}';
    result.push_back(layout.str());
  }
  std::sort(result.begin(), result.end());
  return result;
}

std::vector<std::string> ResourceBindings(ID3D11ShaderReflection* reflection) {
  D3D11_SHADER_DESC shader = {};
  if (FAILED(reflection->GetDesc(&shader)))
    throw std::runtime_error("cannot reflect shader description");

  std::vector<std::string> result;
  for (UINT i = 0; i < shader.BoundResources; ++i) {
    D3D11_SHADER_INPUT_BIND_DESC d = {};
    if (FAILED(reflection->GetResourceBindingDesc(i, &d)))
      throw std::runtime_error("cannot reflect resource binding");
    std::ostringstream s;
    s << d.Type << ':' << d.BindPoint << ':' << d.BindCount << ':' << d.uFlags << ':'
      << d.ReturnType << ':' << d.Dimension << ':' << d.NumSamples;
    result.push_back(s.str());
  }
  std::sort(result.begin(), result.end());
  return result;
}

std::string NormalizeDeclaration(std::string line) {
  const auto first = line.find_first_not_of(" \t\r\n");
  if (first == std::string::npos)
    return {};
  const auto last = line.find_last_not_of(" \t\r\n");
  line = line.substr(first, last - first + 1);
  std::string normalized;
  bool spacing = false;
  for (const unsigned char value : line) {
    if (std::isspace(value)) {
      spacing = !normalized.empty();
      continue;
    }
    if (spacing) normalized.push_back(' ');
    spacing = false;
    normalized.push_back(static_cast<char>(std::tolower(value)));
  }
  return normalized;
}

std::vector<std::string> BindingDeclarations(const std::vector<std::uint8_t>& bytes) {
  ComOwner<ID3DBlob> disassembly;
  const HRESULT hr = D3DDisassemble(bytes.data(), bytes.size(), 0, nullptr, disassembly.put());
  if (FAILED(hr))
    throw std::runtime_error("D3DDisassemble rejected the shader container");
  const std::string text(
      static_cast<const char*>(disassembly.get()->GetBufferPointer()),
      disassembly.get()->GetBufferSize());
  std::istringstream lines(text);
  std::vector<std::string> result;
  std::string line;
  while (std::getline(lines, line)) {
    const auto normalized = NormalizeDeclaration(line);
    if (normalized.rfind("dcl_constantbuffer ", 0) == 0 ||
        normalized.rfind("dcl_resource", 0) == 0 ||
        normalized.rfind("dcl_sampler ", 0) == 0 ||
        normalized.rfind("dcl_uav", 0) == 0)
      result.push_back(normalized);
  }
  std::sort(result.begin(), result.end());
  return result;
}

struct Contract {
  UINT shaderType = 0;
  std::vector<std::string> inputs;
  std::vector<std::string> outputs;
  std::vector<std::string> patchConstants;
  std::vector<std::string> resources;
  std::vector<std::string> constantBuffers;
  std::vector<std::string> bindingDeclarations;
  bool resourceReflectionStripped = false;
  UINT threadGroupX = 0;
  UINT threadGroupY = 0;
  UINT threadGroupZ = 0;
};

Contract Reflect(const std::vector<std::uint8_t>& bytes) {
  ComOwner<ID3D11ShaderReflection> reflection;
  const HRESULT hr = D3DReflect(
      bytes.data(), bytes.size(), IID_ID3D11ShaderReflection,
      reinterpret_cast<void**>(reflection.put()));
  if (FAILED(hr))
    throw std::runtime_error("D3DReflect rejected the shader container");

  D3D11_SHADER_DESC desc = {};
  if (FAILED(reflection.get()->GetDesc(&desc)))
    throw std::runtime_error("cannot read shader description");

  Contract result;
  result.shaderType = D3D11_SHVER_GET_TYPE(desc.Version);
  result.inputs = ReadSignature(reflection.get(), desc.InputParameters,
      &ID3D11ShaderReflection::GetInputParameterDesc);
  result.outputs = ReadSignature(reflection.get(), desc.OutputParameters,
      &ID3D11ShaderReflection::GetOutputParameterDesc);
  result.patchConstants = ReadSignature(reflection.get(), desc.PatchConstantParameters,
      &ID3D11ShaderReflection::GetPatchConstantParameterDesc);
  result.resources = ResourceBindings(reflection.get());
  result.constantBuffers = ConstantBufferLayouts(reflection.get());
  result.bindingDeclarations = BindingDeclarations(bytes);
  result.resourceReflectionStripped = result.resources.empty() && !result.bindingDeclarations.empty();
  if (result.shaderType == D3D11_SHVER_COMPUTE_SHADER)
    reflection.get()->GetThreadGroupSize(&result.threadGroupX, &result.threadGroupY, &result.threadGroupZ);
  return result;
}

bool Compare(const Contract& a, const Contract& b, std::string& reason, bool& usedDeclarationFallback) {
  usedDeclarationFallback = a.resourceReflectionStripped || b.resourceReflectionStripped;
  if (a.shaderType != b.shaderType) reason = "shader stage mismatch";
  else if (a.inputs != b.inputs) reason = "input signature mismatch";
  else if (a.outputs != b.outputs) reason = "output signature mismatch";
  else if (a.patchConstants != b.patchConstants) reason = "patch-constant signature mismatch";
  else if (usedDeclarationFallback && a.bindingDeclarations != b.bindingDeclarations) reason = "executable resource declaration mismatch";
  else if (!usedDeclarationFallback && a.resources != b.resources) reason = "resource binding/type mismatch";
  else if (!usedDeclarationFallback && a.constantBuffers != b.constantBuffers) reason = "constant-buffer layout mismatch";
  else if (a.threadGroupX != b.threadGroupX || a.threadGroupY != b.threadGroupY ||
           a.threadGroupZ != b.threadGroupZ) reason = "compute thread-group mismatch";
  else return true;
  return false;
}

void PrintListDifference(
    const char* label,
    const std::vector<std::string>& original,
    const std::vector<std::string>& replacement) {
  std::cerr << "  original " << label << " (" << original.size() << "):\n";
  for (const auto& value : original)
    std::cerr << "    " << value << '\n';
  std::cerr << "  replacement " << label << " (" << replacement.size() << "):\n";
  for (const auto& value : replacement)
    std::cerr << "    " << value << '\n';
}

void PrintDifference(const Contract& original, const Contract& replacement, const std::string& reason) {
  if (reason == "input signature mismatch")
    PrintListDifference("inputs", original.inputs, replacement.inputs);
  else if (reason == "output signature mismatch")
    PrintListDifference("outputs", original.outputs, replacement.outputs);
  else if (reason == "patch-constant signature mismatch")
    PrintListDifference("patch constants", original.patchConstants, replacement.patchConstants);
  else if (reason == "resource binding/type mismatch")
    PrintListDifference("resources", original.resources, replacement.resources);
  else if (reason == "executable resource declaration mismatch")
    PrintListDifference("binding declarations", original.bindingDeclarations, replacement.bindingDeclarations);
  else if (reason == "constant-buffer layout mismatch")
    PrintListDifference("constant buffers", original.constantBuffers, replacement.constantBuffers);
  else if (reason == "shader stage mismatch")
    std::cerr << "  original stage: " << original.shaderType
              << "\n  replacement stage: " << replacement.shaderType << '\n';
  else if (reason == "compute thread-group mismatch")
    std::cerr << "  original thread group: " << original.threadGroupX << ','
              << original.threadGroupY << ',' << original.threadGroupZ
              << "\n  replacement thread group: " << replacement.threadGroupX << ','
              << replacement.threadGroupY << ',' << replacement.threadGroupZ << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::cerr << "usage: DxbcCompatibilityCheck.exe <original-dxbc> <replacement-dxbc>\n";
    return 1;
  }
  try {
    const auto original = Reflect(ReadFile(argv[1]));
    const auto replacement = Reflect(ReadFile(argv[2]));
    std::string reason;
    bool usedDeclarationFallback = false;
    if (!Compare(original, replacement, reason, usedDeclarationFallback)) {
      std::cerr << "INCOMPATIBLE: " << reason << '\n';
      PrintDifference(original, replacement, reason);
      return 2;
    }
    if (usedDeclarationFallback)
      std::cout << "COMPATIBLE: reflected signatures and disassembled binding declarations match (RDEF resource metadata unavailable)\n";
    else
      std::cout << "COMPATIBLE: reflected DXBC contracts match\n";
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "ERROR: " << e.what() << '\n';
    return 1;
  }
}
