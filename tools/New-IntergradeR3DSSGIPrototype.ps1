[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\r3d-ssgi-sm5-prototype'),
    [string]$FxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\fxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sourcePath = Join-Path $projectRoot 'src\Effects\Lighting\R3DSSGI_SM5.hlsl'
$donorPath = Join-Path $projectRoot 'reference\external\r3d\shaders\prepare\ssgi.frag'
$provenancePath = Join-Path $projectRoot 'reference\external\r3d-provenance.json'
$licensePath = Join-Path $projectRoot 'licenses\R3D-Zlib.txt'

foreach ($required in @($sourcePath, $donorPath, $provenancePath, $licensePath, $FxcPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required SSGI prototype input is missing: $required"
    }
}

$provenance = Get-Content -Raw -LiteralPath $provenancePath | ConvertFrom-Json
if ($provenance.commit -ne '3cb964171a0b90f1d0ec97e061b25021648eec65' -or $provenance.license -ne 'Zlib') {
    throw 'R3D provenance is not the reviewed pinned revision and license.'
}

$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputFull) | Out-Null
$objectPath = Join-Path $outputFull 'R3DSSGI_SM5_ps.obj'
$assemblyPath = Join-Path $outputFull 'R3DSSGI_SM5_ps.asm'
$manifestPath = Join-Path $outputFull 'manifest.json'
$temporaryObject = Join-Path $outputFull ('.R3DSSGI_SM5_ps.' + [guid]::NewGuid().ToString('N') + '.tmp')

try {
    $messages = & $FxcPath /nologo /T ps_5_0 /E main /Ges /WX /O3 /Fo $temporaryObject /Fc $assemblyPath $sourcePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "FXC failed for the R3D SSGI SM5 prototype: $($messages -join ' ')"
    }
    $bytes = [IO.File]::ReadAllBytes($temporaryObject)
    if ($bytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'DXBC') {
        throw 'Compiled SSGI prototype is not a DXBC container.'
    }
    [IO.File]::Copy($temporaryObject, $objectPath, $true)

    $assembly = Get-Content -Raw -LiteralPath $assemblyPath
    foreach ($binding in @('SSGISceneRadiance', 'SSGIViewNormal', 'SSGISceneDepth', 'SSGIConstants', 'SSGILinearClamp')) {
        if ($assembly -notmatch "(?m)^//\s+$binding\s+") {
            throw "Compiled SSGI prototype is missing reflected binding $binding."
        }
    }
    if ($assembly -notmatch '(?m)^//\s+SV_Target\s+0\s+xyzw') {
        throw 'Compiled SSGI prototype is missing SV_Target0.'
    }

    $compilerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($FxcPath)
    $manifest = [ordered]@{
        schemaVersion = 1
        result = 'pass'
        classification = 'engine-neutral-offline-prototype'
        algorithm = 'R3D horizon-based screen-space global illumination'
        sourceMarkedAltered = $true
        donor = [ordered]@{
            upstream = [string]$provenance.upstream
            commit = [string]$provenance.commit
            license = [string]$provenance.license
            path = [IO.Path]::GetRelativePath($projectRoot, $donorPath)
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $donorPath).Hash
        }
        shader = [ordered]@{
            source = [IO.Path]::GetRelativePath($projectRoot, $sourcePath)
            sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
            profile = 'ps_5_0'
            entryPoint = 'main'
            object = [IO.Path]::GetRelativePath($projectRoot, $objectPath)
            objectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
            assembly = [IO.Path]::GetRelativePath($projectRoot, $assemblyPath)
            assemblySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assemblyPath).Hash
        }
        interface = [ordered]@{
            sceneRadiance = 't0'
            viewNormal = 't1'
            sceneDepth = 't2'
            constants = 'b0'
            linearClamp = 's0'
            output = 'SV_Target0 compressed indirect RGB, alpha 1'
            maximumSlices = 8
            maximumStepsPerSlice = 16
        }
        compiler = [ordered]@{
            path = $FxcPath
            version = $compilerInfo.FileVersion
            flags = @('/Ges', '/WX', '/O3')
        }
        policy = [ordered]@{
            remakeBindingsValidated = $false
            runtimeEligible = $false
            installed = $false
            gameFilesTouched = $false
            keyBindingsEmitted = $false
        }
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $utf8)

    [pscustomobject]@{
        result = 'pass'
        profile = 'ps_5_0'
        objectSha256 = $manifest.shader.objectSha256
        manifest = $manifestPath
        runtimeEligible = $false
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryObject -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryObject -Force
    }
}
