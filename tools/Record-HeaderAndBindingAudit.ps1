[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'docs\known-working-code.md'
$backup = "$path.pre-header-binding-audit"

$needle = @'
All 11 donor families retain exactly one reviewed decision; the other eight
remain unresolved rather than guessed. The machine-readable sources are
`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json` and
`src/Adapters/FF7RemakeIntergrade/rebirth-family-relations.json`.

For terminology and controls, see
'@

$replacement = @'
All 11 donor families retain exactly one reviewed decision; the other eight
remain unresolved rather than guessed. The machine-readable sources are
`src/Adapters/FF7RemakeIntergrade/verified-shader-classifications.json` and
`src/Adapters/FF7RemakeIntergrade/rebirth-family-relations.json`.

The live replacement-header audit now passes for all 12 installed shader
replacements: five native ASM replacements preserve Microsoft disassembly
headers, and seven decompiled HLSL replacements preserve their 3Dmigoto source
headers plus exact original binary peers. Do not paste ASM headers into HLSL
files. Evidence: `artifacts/shader-header-audits/20260903-000125-229/manifest.json`.

The five contact-light variants expose position, inverse attenuation radius,
color, and a native flag, but no verified physical emitter radius. Attenuation
radius must not be reused as shadow softness. See
[`contact-shadow-light-binding-audit.md`](contact-shadow-light-binding-audit.md).

For terminology and controls, see
'@

$text = [IO.File]::ReadAllText($path)
$count = ([regex]::Matches($text, [regex]::Escape($needle))).Count
if ($count -ne 1) {
    throw "Expected exactly one ledger insertion point; found $count."
}

Copy-Item -LiteralPath $path -Destination $backup -Force
[IO.File]::WriteAllText($path, $text.Replace($needle, $replacement), [Text.UTF8Encoding]::new($false))

$verify = [IO.File]::ReadAllText($path)
if (-not $verify.Contains('The live replacement-header audit now passes for all 12')) {
    throw 'Ledger verification failed.'
}

[pscustomobject]@{
    status = 'updated'
    path = $path
    backup = $backup
} | ConvertTo-Json
