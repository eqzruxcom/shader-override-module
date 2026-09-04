[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IniPath,
    [string]$ShaderDirectory = 'C:\Games\Final.Fantasy.VII.Remake.Intergrade-InsaneRamZes\End\Binaries\Win64\ShaderCache-Census',
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\analysis\contact-family-live-census.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$artifactRoot = Join-Path $workspace 'artifacts'
$iniPath = [IO.Path]::GetFullPath($IniPath)
$shaderRoot = [IO.Path]::GetFullPath($ShaderDirectory).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($artifactRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must remain beneath workspace artifacts.' }
foreach ($path in @($iniPath,$shaderRoot)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required path is missing: $path" } }

function Get-Section([string[]]$Lines,[string]$Name) {
    $start=[array]::IndexOf($Lines,'['+$Name+']'); if($start-lt0){throw "Section missing: $Name"}
    $result=[Collections.Generic.List[string]]::new()
    for($i=$start+1;$i-lt$Lines.Count;$i++){if($Lines[$i].Trim()-match '^\[[^\]]+\]$'){break};$result.Add($Lines[$i])}
    return @($result)
}
function Get-Setting([string[]]$Lines,[string]$Key) {
    foreach($line in $Lines){if($line-match('^\s*'+[regex]::Escape($Key)+'\s*=\s*(.*?)\s*$')){return $Matches[1]}}
    throw "Setting missing: $Key"
}
function Split-Words([string]$Value){return @(($Value-replace'[,;]',' ')-split'\s+'|Where-Object{$_})}
function Test-Binding([string]$Assembly,[string]$Requested){
    $binding=$Requested.ToLowerInvariant();if($binding-match'^b\d'){$binding='c'+$binding}
    $token='(?<![A-Za-z0-9_])'+[regex]::Escape($binding)+'(?![A-Za-z0-9_])'
    foreach($line in($Assembly-split"`n")){$lower=$line.TrimStart(" `t`r").ToLowerInvariant();if($lower.StartsWith('dcl_')-and$lower-match$token){return $true}}
    return $false
}
function Get-InstructionCount([string]$Assembly){
    $count=0;foreach($line in($Assembly-split"`n")){$lower=$line.TrimStart(" `t`r").ToLowerInvariant();if(-not$lower-or$lower.StartsWith('//')-or$lower.StartsWith('dcl_')-or$lower.StartsWith('globalflags ')-or$lower-match'^.._[45]_0(?:\s|$)'){continue};$count++};return $count
}

$familyNames=@('ShaderRegexUE4FXRemakeContactBaseT5','ShaderRegexUE4FXRemakeContactBaseT4','ShaderRegexUE4FXRemakeContactFrustumT4')
$ini=@(Get-Content -LiteralPath $iniPath)
$families=[ordered]@{}
foreach($name in $familyNames){
    $root=Get-Section $ini $name
    $patternLines=@(Get-Section $ini ($name+'.Pattern')|ForEach-Object{$_.Trim()}|Where-Object{$_-and-not$_.StartsWith(';')})
    $pcre=$patternLines-join''
    $dotnet=[regex]::Replace($pcre,'\(\?P<([A-Za-z_][A-Za-z0-9_]*)>','(?<$1>')
    $dotnet=[regex]::Replace($dotnet,'\(\?P=([A-Za-z_][A-Za-z0-9_]*)\)','\k<$1>')
    $families[$name]=[ordered]@{
        regex=[regex]::new($dotnet,[Text.RegularExpressions.RegexOptions]::IgnoreCase,[TimeSpan]::FromSeconds(3))
        required=@(Split-Words (Get-Setting $root 'required_bindings'));forbidden=@(Split-Words (Get-Setting $root 'forbidden_bindings'))
        minimum=[int](Get-Setting $root 'min_instructions');maximum=[int](Get-Setting $root 'max_instructions')
    }
}

$results=[Collections.Generic.List[object]]::new();$exceptions=[Collections.Generic.List[object]]::new();$timeouts=[Collections.Generic.List[object]]::new()
$files=@(Get-ChildItem -LiteralPath $shaderRoot -Filter '*-cs.txt' -File|Sort-Object Name)
foreach($file in $files){
    $text=([IO.File]::ReadAllText($file.FullName)-replace"`r`n","`n");$count=Get-InstructionCount $text
    $evaluations=[Collections.Generic.List[object]]::new();$accepted=[Collections.Generic.List[string]]::new()
    foreach($entry in $families.GetEnumerator()){
        $raw = $false
        try {
            $raw = $entry.Value.regex.IsMatch($text)
        }
        catch [Text.RegularExpressions.RegexMatchTimeoutException] {
            $timeouts.Add([ordered]@{file=$file.Name;family=$entry.Key})
            continue
        }
        $reasons=[Collections.Generic.List[string]]::new()
        if($count-lt$entry.Value.minimum-or$count-gt$entry.Value.maximum){$reasons.Add("instruction-count $count outside $($entry.Value.minimum)..$($entry.Value.maximum)")}
        foreach($binding in $entry.Value.required){if(-not(Test-Binding $text $binding)){$reasons.Add("missing $binding")}}
        foreach($binding in $entry.Value.forbidden){if(Test-Binding $text $binding){$reasons.Add("forbidden $binding")}}
        if(-not$raw){$reasons.Add('pattern-miss')}
        $ok=$raw-and$reasons.Count-eq0;if($ok){$accepted.Add($entry.Key)}
        if($raw-or($reasons.Count-eq1-and$reasons[0]-eq'pattern-miss')){$evaluations.Add([ordered]@{family=$entry.Key;rawPattern=$raw;accepted=$ok;reasons=@($reasons)})}
    }
    if($accepted.Count){$results.Add([ordered]@{file=$file.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash;instructionCount=$count;families=@($accepted)})}
    $rawAny=@($evaluations|Where-Object rawPattern).Count-gt0
    if(-not$accepted.Count-and$rawAny){$exceptions.Add([ordered]@{file=$file.Name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash;instructionCount=$count;evaluations=@($evaluations|Where-Object rawPattern)})}
}

$known=@('08bb8764f1840179-cs.txt','0e97888f9a8767da-cs.txt','5a9fbefe0ab6f815-cs.txt','62b33a2d1e505241-cs.txt','c30cdc8365df9840-cs.txt')
$report=[ordered]@{
    schemaVersion=1;kind='ff7-remake-live-contact-family-census';analyzedAt=(Get-Date).ToString('o')
    shaderDirectory=$shaderRoot;computeShaderCount=$files.Count;familyIni=$iniPath;familyIniSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $iniPath).Hash
    matches=@($results);matchCount=$results.Count;matchedKnown=@($results|Where-Object file -in $known|ForEach-Object file)
    matchedNew=@($results|Where-Object file -notin $known);rawPatternRejectedExceptions=@($exceptions);exceptionCount=$exceptions.Count;timeouts=@($timeouts)
    policy='New full-contract matches are candidates for automatic coverage. Raw-pattern-only files remain rejected exceptions until instruction/binding/body equivalence is proven.'
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null
[IO.File]::WriteAllText($output,($report|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
if($timeouts.Count){throw "Regex timeout(s): $($timeouts.Count)"}
Write-Host "COMPUTE_SHADERS=$($files.Count)"
Write-Host "FULL_MATCHES=$($results.Count)"
Write-Host "NEW_FULL_MATCHES=$(@($results|Where-Object file -notin $known).Count)"
Write-Host "REJECTED_NEAR_MISSES=$($exceptions.Count)"
Write-Host "REPORT=$output"
