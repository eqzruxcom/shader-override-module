[CmdletBinding()]
param([switch]$InventoryOnly)

# Fresh, local shader-only snapshots. Never mirrors, deletes, or writes to the game.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$gameRoot = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64'
$backupRoot = 'F:\Shader3Dmigoto'
$files = [Collections.Generic.List[object]]::new()
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Assert-NoReparse([string]$Path) {
    $probe = [IO.Path]::GetFullPath($Path)
    while ($probe) {
        if (Test-Path -LiteralPath $probe) {
            if ((Get-Item -Force -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse path not allowed: $probe"
            }
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
}
function Add-File([string]$Path, [string]$Relative) {
    Assert-NoReparse $Path
    if (-not $names.Add($Relative)) { throw "Duplicate backup target: $Relative" }
    $item = Get-Item -Force -LiteralPath $Path
    if ($item.PSIsContainer) { throw "Expected file: $Path" }
    $files.Add([pscustomobject]@{source=$item.FullName; relativePath=$Relative; bytes=$item.Length})
}
function Add-Tree([string]$Path, [string]$Relative) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Missing tree: $Path" }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push([IO.Path]::GetFullPath($Path))
    while ($pending.Count) {
        $current = $pending.Pop()
        foreach ($item in Get-ChildItem -Force -LiteralPath $current) {
            if ($item.Name -eq '.git') { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse entry: $($item.FullName)" }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                Add-File $item.FullName (Join-Path $Relative ([IO.Path]::GetRelativePath($Path, $item.FullName)))
            }
        }
    }
}
foreach ($dir in @('src','docs','tools','runtime','licenses','backups','working-code','reference','artifacts')) {
    Add-Tree (Join-Path $projectRoot $dir) ("project/$dir")
}
foreach ($item in Get-ChildItem -Force -LiteralPath $projectRoot -File) {
    if ($item.Name -in @('README.md','THIRD_PARTY_NOTICES.md','.gitignore') -or $item.Name -like 'README.md.*.bak') {
        Add-File $item.FullName ("project/" + $item.Name)
    }
}
foreach ($dir in @('Mods','ShaderCache','ShaderFixes','FrameAnalysis-2026-08-29-111333','FrameAnalysis-2026-08-29-123153','FrameAnalysis-2026-08-30-211238')) {
    Add-Tree (Join-Path $gameRoot $dir) ("game-shader-state/$dir")
}
foreach ($file in @('d3dx.ini','d3d11.dll')) {
    Add-File (Join-Path $gameRoot $file) ("game-shader-state/$file")
}
$userIni = Join-Path $gameRoot 'd3dx_user.ini'
if (Test-Path -LiteralPath $userIni -PathType Leaf) { Add-File $userIni 'game-shader-state/d3dx_user.ini' }
Assert-NoReparse $backupRoot
$bytes = ($files | Measure-Object bytes -Sum).Sum
$summary = [ordered]@{files=$files.Count;bytes=$bytes;backupRoot=$backupRoot;freeBytes=(Get-PSDrive F).Free}
if ($InventoryOnly) { $summary | ConvertTo-Json; return }
if ($summary.freeBytes -lt ($bytes + 100MB)) { throw 'Insufficient F: free space.' }

$snapshot = Join-Path $backupRoot ('snapshot-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
if (Test-Path -LiteralPath $snapshot) { throw "Refusing existing snapshot: $snapshot" }
Assert-NoReparse $snapshot
$null = New-Item -ItemType Directory -Path $snapshot
$snapshotPrefix = [IO.Path]::GetFullPath($snapshot).TrimEnd('\') + '\'
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-NewJson([string]$Name, $Data) {
    $path = Join-Path $snapshot $Name
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $dataBytes = $utf8.GetBytes(($Data | ConvertTo-Json -Depth 8) + "`n")
        $stream.Write($dataBytes, 0, $dataBytes.Length)
    } finally { $stream.Dispose() }
}
Write-NewJson 'inventory.json' ([ordered]@{createdUtc=[DateTime]::UtcNow.ToString('o');summary=$summary;files=@($files.ToArray())})
$verified = [Collections.Generic.List[object]]::new()
try {
    foreach ($entry in $files) {
        $destination = [IO.Path]::GetFullPath((Join-Path $snapshot $entry.relativePath))
        if (-not $destination.StartsWith($snapshotPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Destination escapes snapshot.'
        }
        Assert-NoReparse $entry.source
        Assert-NoReparse $destination
        if ((Get-Item -LiteralPath $entry.source).Length -ne $entry.bytes) { throw "Source size changed: $($entry.source)" }
        $before = (Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        [IO.File]::Copy($entry.source, $destination, $false)
        $after = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $sourceAfter = (Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash
        if ($before -ne $after -or $before -ne $sourceAfter) { throw "Hash mismatch or source drift: $($entry.source)" }
        $verified.Add([pscustomobject]@{relativePath=$entry.relativePath;source=$entry.source;bytes=$entry.bytes;sha256=$after})
        if ($verified.Count % 500 -eq 0) { Write-Output "Verified $($verified.Count)/$($files.Count) files" }
    }
    $manifest = [ordered]@{
        status='verified'; completedUtc=[DateTime]::UtcNow.ToString('o'); snapshot=$snapshot
        fileCount=$verified.Count; bytes=$bytes; algorithm='SHA256'
        projectRoot=$projectRoot; gameShaderSource=$gameRoot
        scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        exclusions=@('Git administrative metadata at any depth and unrelated audio work','Game executable/assets/saves','Live game logs','Future captures not explicitly listed')
        gameModified=$false; originalsPreserved=$true; files=@($verified.ToArray())
    }
    Write-NewJson 'backup-manifest.json' $manifest
    [pscustomobject]@{status='verified';snapshot=$snapshot;files=$verified.Count;bytes=$bytes;manifestSha256=(Get-FileHash -LiteralPath (Join-Path $snapshot 'backup-manifest.json')).Hash} | ConvertTo-Json
} catch {
    Write-NewJson 'incomplete.json' ([ordered]@{status='incomplete';error=$_.Exception.Message;verifiedFiles=$verified.Count;files=@($verified.ToArray());note='Partial snapshot retained. No files removed.'})
    throw
}
