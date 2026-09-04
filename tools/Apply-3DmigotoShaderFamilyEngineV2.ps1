[CmdletBinding()]
param(
    [string]$ForkRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Backends\3DmigotoFork')
)

$ErrorActionPreference = 'Stop'
$v1 = Join-Path $PSScriptRoot 'Apply-3DmigotoShaderFamilyEngine.ps1'
$text = [IO.File]::ReadAllText($v1)
foreach ($variable in @('regex', 'ini', 'project')) {
    $old = '$' + $variable + ' = [IO.File]::ReadAllText($' + $variable + 'Source)'
    $new = $old + '.Replace("`r`n", "`n")'
    if (-not $text.Contains($old)) { throw "Missing V1 normalization anchor: $variable" }
    $text = $text.Replace($old, $new)
}
$generated = Join-Path ([IO.Path]::GetTempPath()) 'Apply-3DmigotoShaderFamilyEngine.generated.ps1'
[IO.File]::WriteAllText($generated, $text, [Text.UTF8Encoding]::new($false))
try {
    & $generated -ForkRoot $ForkRoot
} finally {
    Remove-Item -LiteralPath $generated -Force -ErrorAction SilentlyContinue
}

