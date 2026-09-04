[CmdletBinding()]
param(
    [string]$ShaderDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderCache-Census',

    [Parameter(Mandatory)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$artifacts = [IO.Path]::GetFullPath((Join-Path $workspace 'artifacts'))
$source = (Resolve-Path -LiteralPath $ShaderDirectory -ErrorAction Stop).Path
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "ShaderDirectory not found: $ShaderDirectory"
}
if (-not $output.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must remain beneath $artifacts"
}
if (Test-Path -LiteralPath $output) {
    throw "OutputDirectory already exists; use a fresh evidence directory: $output"
}

$files = @(Get-ChildItem -LiteralPath $source -File -Filter '*-cs.txt' | Sort-Object Name)
if ($files.Count -lt 1) { throw "No *-cs.txt files found beneath $source" }

[void](New-Item -ItemType Directory -Path $output)
$records = [Collections.Generic.List[object]]::new()

foreach ($file in $files) {
    if ($file.BaseName -notmatch '^(?<hash>[0-9A-Fa-f]{16})-cs$') {
        throw "Unexpected compute-shader filename: $($file.Name)"
    }

    $destinationName = $file.BaseName.ToLowerInvariant() + '.asm'
    $destinationPath = Join-Path $output $destinationName
    [IO.File]::Copy($file.FullName, $destinationPath, $false)

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToUpperInvariant()
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destinationPath).Hash.ToUpperInvariant()
    if ($sourceHash -ne $destinationHash) {
        throw "Mirror hash mismatch: $($file.Name)"
    }

    $records.Add([pscustomobject][ordered]@{
        shader = $file.BaseName.ToLowerInvariant()
        source = $file.FullName
        mirror = $destinationPath
        length = $file.Length
        sha256 = $sourceHash
    })
}

$manifest = [ordered]@{
    schemaVersion = 1
    purpose = 'Byte-identical .asm mirror of the live 3Dmigoto compute-shader census for existing structural analyzers.'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    sourceDirectory = $source
    outputDirectory = $output
    computeShaderCount = $records.Count
    shaders = @($records)
}

$manifestPath = Join-Path $output 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "PASS: mirrored $($records.Count) compute shaders byte-for-byte."
Write-Host "Manifest: $manifestPath"
