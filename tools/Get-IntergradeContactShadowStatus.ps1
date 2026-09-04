[CmdletBinding()]
param([string]$GeneratedRuntimeDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/generated-runtime/FF7RemakeIntergradeContactAllLights-live-v1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$generated=(Resolve-Path -LiteralPath $GeneratedRuntimeDirectory).Path.TrimEnd('\')
if(-not $generated.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Status output escaped workspace.'}
$baseline=Get-Content -LiteralPath (Join-Path $generated 'live-reload-baseline.json') -Raw | ConvertFrom-Json
$mode=if($baseline.PSObject.Properties.Name -contains 'mode') {$baseline.mode} else {'author-contact-shadow-rays'}
$receipt=Get-Content -LiteralPath $baseline.installReceipt -Raw | ConvertFrom-Json
if($receipt.adapterId -ne 'FF7RemakeIntergradeContactShadows') {throw 'Wrong overlay receipt.'}
$changed=@(foreach($file in $receipt.files) {
    $path=Join-Path $receipt.targetRoot $file.relativePath
    if(-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $file.installedSha256) {$file.relativePath}
})
$protectedChanged=@(foreach($file in $baseline.protectedLiveFiles) {
    $path=Join-Path $receipt.targetRoot $file.path
    if(-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) {$file.path}
})
$process=Get-Process -Id $baseline.processId -ErrorAction SilentlyContinue
$alive=$null -ne $process -and $process.Path -eq (Join-Path $receipt.targetRoot 'ff7remake_.exe')
$responding=$alive -and $process.Responding
$text='';$truncated=$false;$bytes=0
$stream=[IO.File]::Open($baseline.logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try {
    $truncated=$stream.Length -lt [long]$baseline.byteOffset
    if(-not $truncated) {
        $null=$stream.Seek([long]$baseline.byteOffset,[IO.SeekOrigin]::Begin)
        $bytes=$stream.Length-[long]$baseline.byteOffset
        $reader=[IO.StreamReader]::new($stream)
        try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()}
    }
} finally {$stream.Dispose()}
$errors=@($text -split "`r?`n" | Where-Object {$_ -match '(?i)unrecognised|syntax error|error assembling|failed to reload|error.*(?:contact|\.ini|shader)|warning.*(?:contact|duplicate|override)'})
$keySeen=$text -match '(?im)^\[Key\\Mods\\ContactShadows\.ini\\UE4FXContactHome\]\s*$'
$reloadSeen=$text -match '(?im)^> d3dx\.ini reloaded\s*$'
$edgeKeys=@(if($mode -in @('rebirth-contact-left-edge-fade-experiment-v1','rebirth-contact-left-edge-profile-experiment-v2')) {
    foreach($digit in 0..9) {
        $custom=$mode -eq 'rebirth-contact-left-edge-profile-experiment-v2' -and $digit -eq 1
        @{key=[string]$digit;percent=$(if($custom){4}else{$digit});cutoffPercent=$(if($custom){.5}else{0});parsed=($text -match ('(?im)^\[Key\\Mods\\ContactShadows\.ini\\UE4FXContactEdge'+$digit+'\]\s*$'))}
    }
})
$edgeKeysComplete=@($edgeKeys|Where-Object {-not $_.parsed}).Count -eq 0
$shaders=@(foreach($hash in $baseline.expectedShaders) {
    [ordered]@{
        hash=$hash
        assemblyLoadSeen=($text -match ('(?im)Re-Loading replacement ASM code from '+$hash+'-cs\.txt\s*$'))
        creationSeen=($text -match ('(?im)^> successfully reloaded shader: '+$hash+'-cs\.txt\s*$'))
        overrideParsed=($text -match ('(?im)^\[ShaderOverride\\Mods\\ContactShadows\.ini\\UE4FXContact'+$hash+'\]\s*$'))
    }
})
$complete=@($shaders | Where-Object {-not $_.assemblyLoadSeen -or -not $_.creationSeen -or -not $_.overrideParsed}).Count -eq 0
$classification=if($changed.Count -or $protectedChanged.Count) {'live-files-changed'}
elseif(-not $alive -or $truncated) {'process-or-log-restarted-rebaseline-required'}
elseif($errors.Count) {'reload-errors-detected'}
elseif(-not $reloadSeen -or -not $keySeen) {'pending-F10'}
elseif(-not $edgeKeysComplete) {'pending-direct-edge-key-parsing'}
elseif(-not $complete) {'pending-all-five-shader-loads'}
else {'passed-parser-and-five-native-asm-reloads'}
$report=[ordered]@{
    schemaVersion=1;checkedAtUtc=[DateTime]::UtcNow.ToString('o');classification=$classification;mode=$mode
    processId=$baseline.processId;processAlive=$alive;processResponding=$responding
    logBytesSinceInstall=$bytes;keyParsed=$keySeen;configReloadSeen=$reloadSeen;shaders=$shaders
    edgeKeys=$edgeKeys;currentFadePercent='Not inferred from INI default'
    errorLines=$errors;changedPayloadFiles=$changed;changedProtectedFiles=$protectedChanged
    visualResult='Requires user observation; parser/creation success is not proof of correct pixels'
    currentToggleState='Not inferred from INI default';performanceVerified=$false
}
[IO.File]::WriteAllText((Join-Path $generated 'contact-live-status.json'),($report|ConvertTo-Json -Depth 7)+"`n",[Text.UTF8Encoding]::new($false))
[pscustomobject]$report
