[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory)][string]$GameExecutable,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')][string]$CaptureId,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$KitDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\ue4-validation-capture-kit'),
    [string]$InstallManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$kitRoot = (Resolve-Path -LiteralPath $KitDirectory).Path.TrimEnd('\')
$kitManifestPath = Join-Path $kitRoot 'capture-kit-manifest.json'
$exePath = (Resolve-Path -LiteralPath $GameExecutable).Path
$targetRoot = (Split-Path -Parent $exePath).TrimEnd('\')
$utf8 = [Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($InstallManifestPath)) {
    $InstallManifestPath = Join-Path $projectPath "artifacts\installed-validation-capture-kits\$CaptureId.json"
}
$installManifestFull = [IO.Path]::GetFullPath($InstallManifestPath)
if (-not $installManifestFull.StartsWith($projectPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install manifest must remain inside the project.' }
if (-not (Test-Path -LiteralPath $kitManifestPath -PathType Leaf)) { throw 'Capture-kit manifest is missing.' }

$kit = Get-Content -Raw -LiteralPath $kitManifestPath | ConvertFrom-Json
if ([bool]$kit.containsReplacementShaders -or [bool]$kit.containsGameShaderHashes -or -not [bool]$kit.failClosed) {
    throw 'Capture kit failed its neutrality contract.'
}
$runtimeFiles = @('d3d11.dll','d3dcompiler_46.dll','nvapi64.dll','d3dx.ini')
foreach ($name in $runtimeFiles) {
    $record = @($kit.files | Where-Object relativePath -eq $name)
    if ($record.Count -ne 1) { throw "Capture kit does not contain exactly one $name record." }
    $source = Join-Path $kitRoot $name
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne [string]$record[0].sha256) { throw "Capture-kit payload hash mismatch: $name" }
}
$processName = [IO.Path]::GetFileNameWithoutExtension($exePath)
if (@(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count) { throw "Refusing installation while $processName is running." }

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$backupRoot = Join-Path $projectPath "backups\UE4ValidationCaptureKit\$CaptureId\$timestamp"
$records = [Collections.Generic.List[object]]::new()
if (-not $PSCmdlet.ShouldProcess($targetRoot, "Install neutral capture runtime with backup at $backupRoot")) { return }
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
try {
    foreach ($name in $runtimeFiles) {
        $source = Join-Path $kitRoot $name
        $destination = Join-Path $targetRoot $name
        $hadOriginal = Test-Path -LiteralPath $destination -PathType Leaf
        $originalSha = $null
        if ($hadOriginal) {
            $backup = Join-Path $backupRoot $name
            Copy-Item -LiteralPath $destination -Destination $backup
            $originalSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash
        }
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $installedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        if ($installedSha -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash) { throw "Installed hash mismatch: $name" }
        $records.Add([pscustomobject][ordered]@{ relativePath=$name; hadOriginal=$hadOriginal; originalSha256=$originalSha; installedSha256=$installedSha })
    }
} catch {
    foreach ($record in @($records) | Sort-Object relativePath -Descending) {
        $destination = Join-Path $targetRoot ([string]$record.relativePath)
        if ([bool]$record.hadOriginal) { Copy-Item -LiteralPath (Join-Path $backupRoot ([string]$record.relativePath)) -Destination $destination -Force }
        elseif (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination -Force }
    }
    throw
}

$manifest = [ordered]@{
    schemaVersion = 1
    captureId = $CaptureId
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    gameExecutable = [ordered]@{ path=$exePath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exePath).Hash }
    targetRoot = $targetRoot
    kitManifest = $kitManifestPath.Substring($projectPath.Length + 1).Replace('\','/')
    kitManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $kitManifestPath).Hash
    backupRoot = $backupRoot
    files = @($records)
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $installManifestFull)) | Out-Null
$manifestJson = ($manifest | ConvertTo-Json -Depth 7) + [Environment]::NewLine
$manifestSchema = Join-Path $projectPath 'src\Engine\UE4\ValidationCapture\install-manifest.schema.json'
if (-not ($manifestJson | Test-Json -SchemaFile $manifestSchema -ErrorAction Stop)) { throw 'Generated install manifest failed its schema.' }
[IO.File]::WriteAllText($installManifestFull, $manifestJson, $utf8)
& (Join-Path $PSScriptRoot 'Assert-UE4ValidationManifest.ps1') -Kind Install -Path $installManifestFull -ProjectRoot $projectPath | Out-Null
[pscustomobject]@{ CaptureId=$CaptureId; InstalledFiles=$records.Count; Target=$targetRoot; Backup=$backupRoot; Manifest=$installManifestFull; Result='installed'; LaunchRequired=$true }
