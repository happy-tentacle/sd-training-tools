param (
    [Parameter(Mandatory = $false)] [string] $Path,
    [Parameter(Mandatory = $false)] [string] $Format,
    [Parameter(Mandatory = $false)] [Switch] $ShortFormat,
    [Parameter(Mandatory = $false)] [Switch] $LongFormat,
    [Parameter(Mandatory = $false)] [Switch] $KeepPromptFromFile,
    [Parameter(Mandatory = $false)] [string[]] $KeywordMapping,
    [Parameter(Mandatory = $false)] [string[]] $Sort = ("Series", "Name")
)

$ErrorActionPreference = "Stop"

if ($Format) {
}
elseif ($ShortFormat) {
    $Format = '| <lora:$Lora:$LoraWeight> $Prompt'
}
else {
    $Format = '| ($Series - $Character by $Author:0) <lora:$Lora:$LoraWeight> $Prompt'
}

$CharacterLoras = & "$PSScriptRoot\get-character-loras.ps1"
$CharactersByLora = $CharacterLoras.CharactersByLora

if ($Path) {
    $LorasFromPath = Get-ChildItem -Path $Path -File `
    | Get-Content -Encoding ascii -TotalCount 40 `
    | Select-String -Pattern '(?s)<lora:([^>:]+)(?:\:([^>]+))?>(?: *,)? *([^\r\n<]+)' -AllMatches | % { $_.Matches } `
    | % { 
        $Lora = $_.Groups[1].Value
        $Prompt = $_.Groups[3].Value
        $Characters = $CharactersByLora[$Lora.ToLower()]

        if (@($Characters).Length -eq 1) {
            $Character = $Characters | Select-Object -First 1
        }
        else {
            $Character = $Characters | Where-Object { $Prompt -imatch "\b$($_.TriggerWord)\b" } | Select-Object -First 1
        }

        if ($KeepPromptFromFile) {
            $Character = $Character | % { $_.Clone() }
            $Character | ForEach-Object { $_.Prompt = $Prompt }
        }

        @{ 
            Lora       = $Lora
            LoraWeight = $_.Groups[2].Value
            Prompt     = $Prompt
            Characters = $Characters
            Character  = $Character
        }; 
    }

    Write-Debug "Loras:`n$($LorasFromPath | % { "Lora: $($_.Lora), Character: $($_.Character?.Name)" } | Join-String -Separator "`n")"

    $Characters = $LorasFromPath | % { $_.Character } | Where-Object { !!$_ } | Sort-Object -Property $Sort
}
else {
    $Characters = $CharacterLoras.Characters
}

foreach ($Character in $Characters) {
    $Series = $Character.Series
    $Name = $Character.Name
    $Author = $Character.Author
    $LoraWeight = $Character.LoraWeight
    $Prompt = $Character.Prompt
    $Lora = $Character.Lora

    if ($Author) {
        $Name = $Name -ireplace $AuthorSuffix -ireplace " \($($Character.Author)\)"
    }
    else {
        $Author = "unknown"
    }

    if ($Character.OutputName) {
        $Lora = $Character.OutputName
    }

    $Format `
        -ireplace '\$Series\b', $Series `
        -ireplace '\$Character\b', $Name `
        -ireplace '\$Author\b', $Author `
        -ireplace '\$Lora\b', $Lora `
        -ireplace '\$LoraWeight\b', $LoraWeight `
        -ireplace '\$Prompt\b', $Prompt
}