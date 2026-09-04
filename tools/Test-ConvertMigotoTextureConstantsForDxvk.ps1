[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$converter = Join-Path $PSScriptRoot 'Convert-MigotoTextureConstantsForDxvk.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ('ue4fx-migoto-texture-bake-test-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-Rejected([scriptblock]$Action, [string]$Expected, [string]$Label) {
    $rejected = $false
    try { & $Action }
    catch {
        $rejected = $_.Exception.Message -match [regex]::Escape($Expected)
        if (-not $rejected) { throw "Unexpected rejection for ${Label}: $($_.Exception.Message)" }
    }
    if (-not $rejected) { throw "Expected rejection was not raised: $Label" }
    Write-Host "PASS: rejected $Label."
}

try {
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $source = Join-Path $work 'fixture-cs.txt'
    $map = Join-Path $work 'map.json'
    $output = Join-Path $work 'fixture-cs_replace.asm'
    [IO.File]::WriteAllText($source, @'
cs_5_0
dcl_resource_texture1d (float,float,float,float) t120
dcl_temps 3
ld_indexable(texture1d)(float,float,float,float) r0.x, l(31, 0, 0, 0), t120.xyzw
ld_indexable [precise](texture1d)(float,float,float,float) r1.xyzw, l(31, 0, 0, 0), t120.zxyw
ld_indexable [precise(xy)](texture1d)(float,float,float,float) r2.xy, l(29, 0, 0, 0), t120.xyzw
ret
'@.Trim() + [Environment]::NewLine, $utf8)
    $constantMap = [ordered]@{
        schemaVersion=1;kind='migoto-texture1d-constant-map';resource='t120'
        entries=[ordered]@{'29'=@(0.06,0.0,0.0,0.0);'31'=@(1.0,-1.0,1.0,100.0)}
    }
    [IO.File]::WriteAllText($map, (($constantMap|ConvertTo-Json -Depth 5)+[Environment]::NewLine), $utf8)

    & $converter -SourcePath $source -ConstantMapPath $map -OutputPath $output
    $manifestPath = $output + '.specialization.json'
    if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Converter did not publish output and manifest.' }
    $text = Get-Content -Raw -LiteralPath $output
    foreach ($expected in @(
        'mov r0.x, l(1.0, 0.0, 0.0, 0.0)',
        'mov r1.xyzw, l(1.0, 1.0, -1.0, 100.0)',
        'mov r2.xy, l(0.06, 0.0, 0.0, 0.0)'
    )) { if (-not $text.Contains($expected)) { throw "Missing baked instruction: $expected" } }
    $activeT120 = @($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' -and $_ -match '(?<![A-Za-z0-9_])t120(?![A-Za-z0-9_])' })
    if ($activeT120.Count) { throw "Active t120 use remains after specialization: $($activeT120 -join '; ')" }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.declarationsRemoved-ne1-or$manifest.loadsReplaced-ne3-or$manifest.outputSha256-ne(Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()-or$manifest.runtimeEligible-ne$false-or$manifest.installed-ne$false) { throw 'Specialization manifest is incomplete or inconsistent.' }

    & $converter -SourcePath $source -ConstantMapPath $map -OutputPath $output

    $missingMap = Join-Path $work 'missing-map.json'
    $missing = [ordered]@{schemaVersion=1;kind='migoto-texture1d-constant-map';resource='t120';entries=[ordered]@{'29'=@(0.06,0,0,0)}}
    [IO.File]::WriteAllText($missingMap,(($missing|ConvertTo-Json -Depth 5)+[Environment]::NewLine),$utf8)
    Assert-Rejected { & $converter -SourcePath $source -ConstantMapPath $missingMap -OutputPath (Join-Path $work 'missing.asm') } 'No baked value exists for t120 index 31' 'missing controller index'

    $unsupported = Join-Path $work 'unsupported.txt'
    [IO.File]::WriteAllText($unsupported, "cs_5_0`ndcl_resource_texture1d (float,float,float,float) t120`nmov r0.x, t120.x`nret`n", $utf8)
    Assert-Rejected { & $converter -SourcePath $unsupported -ConstantMapPath $map -OutputPath (Join-Path $work 'unsupported.asm') } 'Unsupported t120 use remains' 'unsupported private-resource use'

    Add-Content -LiteralPath $source -Value '// source evidence mismatch' -Encoding utf8
    Assert-Rejected { & $converter -SourcePath $source -ConstantMapPath $map -OutputPath $output } 'Refusing to overwrite mismatched prior specialization evidence' 'mismatched specialization overwrite'

    Write-Host 'PASS: 3Dmigoto texture-controller baking is exact, exhaustive, fail-closed, idempotent, and evidence-preserving.'
}
finally {
    if (Test-Path -LiteralPath $work) {
        $resolved = [IO.Path]::GetFullPath($work);$leaf=Split-Path -Leaf $resolved
        if(-not$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)-or-not$leaf.StartsWith('ue4fx-migoto-texture-bake-test-',[StringComparison]::Ordinal)){throw"Refusing to remove unexpected test path: $resolved"}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
