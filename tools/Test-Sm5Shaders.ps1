[CmdletBinding()]
param(
    [string]$FxcPath,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'artifacts'
}

if ([string]::IsNullOrWhiteSpace($FxcPath)) {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $FxcPath = Get-ChildItem -LiteralPath $kitsRoot -Filter fxc.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\fxc\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if ([string]::IsNullOrWhiteSpace($FxcPath) -or -not (Test-Path -LiteralPath $FxcPath -PathType Leaf)) {
    throw 'FXC was not found. Install the Windows SDK or pass -FxcPath explicitly.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$jobs = @(
    @{ Source = 'src\Tests\PostProcessSmoke_ps.hlsl'; Profile = 'ps_5_0'; Base = 'PostProcessSmoke_ps' },
    @{ Source = 'src\Tests\LightingSmoke_ps.hlsl'; Profile = 'ps_5_0'; Base = 'LightingSmoke_ps' },
    @{ Source = 'src\Tests\RuntimeSettingsSmoke_ps.hlsl'; Profile = 'ps_5_0'; Base = 'RuntimeSettingsSmoke_ps' },
    @{ Source = 'src\Tests\ViewReconstructionSmoke_cs.hlsl'; Profile = 'cs_5_0'; Base = 'ViewReconstructionSmoke_cs' }
)

$results = foreach ($job in $jobs) {
    $sourcePath = Join-Path $repoRoot $job.Source
    $objectPath = Join-Path $OutputDirectory ($job.Base + '.cso')
    $assemblyPath = Join-Path $OutputDirectory ($job.Base + '.asm')

    $compilerOutput = & $FxcPath /nologo /Ges /WX /O3 /E main /T $job.Profile /Fo $objectPath /Fc $assemblyPath $sourcePath 2>&1
    $compilerExitCode = $LASTEXITCODE
    if ($compilerExitCode -ne 0) {
        $compilerOutput | ForEach-Object { Write-Error $_ }
        throw "FXC failed for $sourcePath with exit code $compilerExitCode."
    }
    $compilerOutput | ForEach-Object { Write-Verbose $_ }

    $object = Get-Item -LiteralPath $objectPath
    [pscustomobject]@{
        source = $job.Source
        profile = $job.Profile
        byteCount = $object.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectPath).Hash
        objectPath = $objectPath
        assemblyPath = $assemblyPath
    }
}

$manifestPath = Join-Path $OutputDirectory 'sm5-smoke-test-manifest.json'
[ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    compiler = $FxcPath
    shaders = @($results)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$results | Format-Table source, profile, byteCount, sha256 -AutoSize
Write-Output "SM5 smoke tests passed: $(@($results).Count) shader(s)."
Write-Output "Manifest: $manifestPath"