[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Capture','Install')][string]$Kind,
    [Parameter(Mandatory)][string]$Path,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$manifestPath = (Resolve-Path -LiteralPath $Path).Path
$schemaName = if ($Kind -eq 'Capture') { 'capture-manifest.schema.json' } else { 'install-manifest.schema.json' }
$schemaPath = Join-Path $projectPath "src\Engine\UE4\ValidationCapture\$schemaName"
$json = Get-Content -Raw -LiteralPath $manifestPath
$schemaErrors = @()
if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable +schemaErrors)) {
    $detail = @($schemaErrors | ForEach-Object { $_.Exception.Message }) -join '; '
    throw "$Kind validation manifest failed schema validation: $detail"
}
$manifest = $json | ConvertFrom-Json

if ($Kind -eq 'Capture') {
    $records = @($manifest.shaders)
    if ([int]$manifest.capturedShaderCount -ne $records.Count) { throw 'Captured shader count does not match shader records.' }
    $identities = @($records | ForEach-Object { ([string]$_.shader).ToLowerInvariant() })
    if (@($identities | Sort-Object -Unique).Count -ne $identities.Count) { throw 'Capture manifest contains duplicate shader identities.' }
    foreach ($record in $records) {
        $identity = ([string]$record.shader).ToLowerInvariant()
        if ([string]$record.binary -ne "dxbc/$identity.bin" -or [string]$record.assembly -ne "assembly/$identity.asm") {
            throw "Capture artifact paths do not match shader identity: $identity"
        }
    }
}
else {
    $expected = @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini') | Sort-Object
    $actual = @($manifest.files | ForEach-Object { [string]$_.relativePath }) | Sort-Object
    if (($expected -join '|') -ne ($actual -join '|')) { throw 'Install manifest does not contain exactly the four neutral runtime targets.' }
    $exePath = [IO.Path]::GetFullPath([string]$manifest.gameExecutable.path)
    $targetRoot = [IO.Path]::GetFullPath([string]$manifest.targetRoot).TrimEnd('\')
    if (-not $targetRoot.Equals((Split-Path -Parent $exePath).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Install target root does not match the game executable directory.'
    }
    $backupRoot = [IO.Path]::GetFullPath([string]$manifest.backupRoot).TrimEnd('\')
    $allowedBackup = [IO.Path]::GetFullPath((Join-Path $projectPath "backups\UE4ValidationCaptureKit\$([string]$manifest.captureId)")).TrimEnd('\')
    if (-not $backupRoot.StartsWith($allowedBackup + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Install backup root escaped the capture-specific backup directory.'
    }
}

$manifest
