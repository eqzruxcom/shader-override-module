[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/generated-runtime/FF7RemakeIntergradeContactLightCut-live-v1'),
    [switch]$Install
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd('\')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(-not $output.StartsWith((Join-Path $repo 'artifacts/generated-runtime')+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)) {throw 'Use a new generated-runtime directory.'}
$priorPath=Join-Path $repo 'artifacts/installed-contact-shadows-overlay-v1.json'
$prior=Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json
$live=[IO.Path]::GetFullPath($prior.targetRoot).TrimEnd('\')
$exe=Join-Path $live 'ff7remake_.exe'
if((Get-FileHash -LiteralPath $exe).Hash -ne $prior.executable.sha256) {throw 'Executable changed.'}
foreach($file in $prior.files) {if((Get-FileHash -LiteralPath (Join-Path $live $file.relativePath)).Hash -ne $file.installedSha256) {throw 'Previous contact overlay changed.'}}
$priorGenerated=Join-Path $repo 'artifacts/generated-runtime/FF7RemakeIntergradeContactShadows-live-v2'
$previousStatus=& (Join-Path $PSScriptRoot 'Get-IntergradeContactShadowStatus.ps1') -GeneratedRuntimeDirectory $priorGenerated
if($previousStatus.classification -ne 'passed-parser-and-five-native-asm-reloads' -or -not $previousStatus.processResponding) {throw 'Previous live load is not healthy.'}
$baseline=Get-Content -LiteralPath (Join-Path $priorGenerated 'live-reload-baseline.json') -Raw | ConvertFrom-Json
$candidateRoot=Join-Path $repo 'artifacts/contact-shadow-candidate-20260830-v3'
$candidate=Get-Content -LiteralPath (Join-Path $candidateRoot 'candidate.json') -Raw | ConvertFrom-Json
$assemblyTool=Join-Path $repo 'artifacts/shader-assembler-build/bin/cmd_Decompiler.exe'
$runner=Join-Path $repo 'artifacts/contact-shadows-port-20260830-v10/ContactShadowWarpTest.exe'
$installPath=Join-Path $repo 'artifacts/installed-contact-light-cut-overlay-v1.json'
if(Test-Path -LiteralPath $installPath) {throw 'Receipt exists; preserve it.'}
if(-not $PSCmdlet.ShouldProcess($output,'Build a temporary Home-toggle cut of native light 50, with original calculations OFF')) {return}
$utf8=[Text.UTF8Encoding]::new($false)
foreach($path in @($output,(Join-Path $output 'validation'),(Join-Path $output 'ShaderFixes'),(Join-Path $output 'Mods'))) {$null=New-Item -ItemType Directory -Path $path}
$files=@();$checks=@();$binaries=@()
foreach($v in $candidate.variants) {
    $original=Join-Path $candidateRoot ('validation/'+$v.shaderHash+'-original.bin')
    if((Get-FileHash -LiteralPath $original).Hash -ne $v.originalSha256) {throw 'Original shader mismatch.'}
    $source=Get-Content -LiteralPath (Join-Path $candidateRoot ('validation/'+$v.shaderHash+'-original.asm'))
    $source=@($source | ForEach-Object {$_.Trim()} | Where-Object {$_ -and -not $_.StartsWith('//')})
    foreach($anchor in @($v.indexCapture,$v.insertion,('dcl_temps '+$v.originalTemporaryCount))) {
        if(@($source | Where-Object {$_ -ceq $anchor}).Count -ne 1) {throw 'Native diagnostic anchor mismatch.'}
    }
    $index='r'+$v.originalTemporaryCount
    $control='r'+($v.originalTemporaryCount+1)
    $block=@(
        "ld_indexable(texture1d)(float,float,float,float) $control.xy, l(31, 0, 0, 0), t120.xyzw",
        "eq $control.x, $control.x, l(1.000000)","if_nz $control.x",
        "ftou $control.y, $control.y","ieq $control.x, $control.y, $index.x","if_nz $control.x",
        ('mov '+$v.diffuse+', l(0,0,0,0)'),('mov '+$v.specular+', l(0,0,0,0)'),
        'endif','endif')
    $patched=[Collections.Generic.List[string]]::new();$originalMapped=[Collections.Generic.List[string]]::new()
    foreach($line in $source) {
        if($line -ceq $v.insertion) {foreach($insert in $block) {$patched.Add($insert)}}
        if($line -eq ('dcl_temps '+$v.originalTemporaryCount)) {
            $patched.Add('dcl_resource_texture1d (float,float,float,float) t120')
            $patched.Add('dcl_temps '+($v.originalTemporaryCount+2))
        } else {$patched.Add($line)}
        $originalMapped.Add($line)
        if($line -ceq $v.indexCapture) {$patched.Add('mov '+$index+'.x, '+($v.indexCapture -split ',')[0].Substring(4))}
    }
    if(($originalMapped -join "`n") -cne ($source -join "`n")) {throw 'Original instruction order changed.'}
    $asm=Join-Path $output ('validation/'+$v.shaderHash+'-cut.asm')
    [IO.File]::WriteAllText($asm,($patched -join "`n")+"`n",$utf8)
    $messages=& $assemblyTool -a --copy-reflection $original $asm 2>&1;$code=$LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $output ('validation/'+$v.shaderHash+'-assemble.log')),($messages|Out-String),$utf8)
    if($code -ne 0) {throw 'Diagnostic assembly failed.'}
    $binary=[IO.Path]::ChangeExtension($asm,'.shdr');$binaries+=$binary
    $relative='ShaderFixes/'+$v.shaderHash+'-cs.txt'
    Copy-Item -LiteralPath $asm -Destination (Join-Path $output $relative)
    $files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash}
    $checks+=@{shaderHash=$v.shaderHash;originalSha256=$v.originalSha256;binarySha256=(Get-FileHash -LiteralPath $binary).Hash;originalInstructionLines=$source.Count;temporaryCount=($v.originalTemporaryCount+2);nativeDiffuse=$v.diffuse;nativeSpecular=$v.specular}
}
$messages=& $runner --validate-cs @binaries 2>&1;$code=$LASTEXITCODE
[IO.File]::WriteAllText((Join-Path $output 'validation/create-shaders.log'),($messages|Out-String),$utf8)
if($code -ne 0 -or @($messages | Where-Object {$_ -match '^PASS CreateComputeShader:'}).Count -ne 5) {throw 'Diagnostic shader creation failed.'}
$relative='Mods/ContactShadows.ini'
$ini=Get-Content -LiteralPath (Join-Path $live $relative) -Raw
$ini=($ini -split "`r?`n" | Where-Object {-not $_.StartsWith(';')}) -join "`r`n"
$ini="; TEMPORARY diagnostic: Home ON cuts native light 50 contributions, NOT contact tracing.`r`n; Home OFF retains original light calculations. Page Down unchanged.`r`n"+$ini
[IO.File]::WriteAllText((Join-Path $output $relative),$ini+"`r`n",$utf8)
$files+=@{relativePath=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $output $relative)).Hash}
$manifest=[ordered]@{
    schemaVersion=1;adapterId='FF7RemakeIntergradeContactShadows';mode='temporary-single-light-contribution-cut'
    createdAtUtc=[DateTime]::UtcNow.ToString('o');licensedRegexDependency=$false;diagnosticOnly=$true;releaseEligible=$false
    executable=$prior.executable;files=$files;checks=$checks;shaderCreationChecks=5;shaderExecutionTested=$false
    selectedLight=50;key='Home';defaultEnabled=$false;rayTracingEnabled=$false
    purpose='Diagnose user-reported no visible contact-shadow change; separate live selected-light contribution from ray calculation'
    predecessorReceipt=$priorPath;protectedLiveFiles=$baseline.protectedLiveFiles
    limitations=@('Native calculation OFF; added index/control instructions still have cost','No live visual result yet','This diagnostic is not an author effect or preferred preset')
}
[IO.File]::WriteAllText((Join-Path $output 'runtime-manifest.json'),($manifest|ConvertTo-Json -Depth 8)+"`n",$utf8)
if($Install -and $PSCmdlet.ShouldProcess($live,'Back up the contact-ray patch and install a default-OFF single-light cut diagnostic')) {
    $offset=(Get-Item -LiteralPath $baseline.logPath).Length
    & (Join-Path $PSScriptRoot 'Install-UE4GeneratedRuntimeOverlay.ps1') -GeneratedRuntimeDirectory $output -InstallManifestPath $installPath
    foreach($f in $baseline.protectedLiveFiles) {if((Get-FileHash -LiteralPath (Join-Path $live $f.path)).Hash -ne $f.sha256) {throw 'Protected live file changed.'}}
    $next=[ordered]@{schemaVersion=1;mode=$manifest.mode;processId=$baseline.processId;capturedAtUtc=[DateTime]::UtcNow.ToString('o');logPath=$baseline.logPath;byteOffset=$offset;installReceipt=$installPath;expectedShaders=$baseline.expectedShaders;defaultEnabled=$false;key='Home';reloadRequired=$true;protectedLiveFiles=$baseline.protectedLiveFiles}
    [IO.File]::WriteAllText((Join-Path $output 'live-reload-baseline.json'),($next|ConvertTo-Json -Depth 7)+"`n",$utf8)
}
[pscustomobject]@{State='temporary-light-cut-staged';InstallRequested=[bool]$Install;Output=$output;Key='Home';Default='OFF';CutLight=50}
