param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $false)] [string] $Format,
    [Parameter(Mandatory = $false)] [Switch] $Force,
    [Parameter(Mandatory = $false)] [Switch] $Overwrite,
    [Parameter(Mandatory = $false)] [Switch] $DryRun,
    [Parameter(Mandatory = $false)] [Switch] $IncludeNoCharacter,
    [Parameter(Mandatory = $false)] [Switch] $SkipIfMissingKeyword,
    [Parameter(Mandatory = $false)] [Switch] $FindCharacterByTrigger,
    [Parameter(Mandatory = $false)] [Switch] $Recurse,
    [Parameter(Mandatory = $false)] [string[]] $KeywordMapping
)

$ErrorActionPreference = "Stop"

if (!$Format) {
    $Format = '($Series) [$CharacterAndAuthor] $FileNameBase$FileNameSuffix'
}

$KeywordMap = @{}
if ($KeywordMapping) {
    $KeywordMapping `
    | Select-String -Pattern '^([^=]+)(?:=([^=]+))$' -AllMatches `
    | % { $_.Matches } `
    | ForEach-Object {
        $Keyword = $_.Groups[1].Value
        $MappedValue = $_.Groups[2]?.Value
        if (!$MappedValue) {
            $MappedValue = $Keyword
        }
        $KeywordMap[$Keyword.ToLower()] = $MappedValue
    }

}

$CharacterLoras = & "$PSScriptRoot\get-character-loras.ps1"
$CharactersByLora = $CharacterLoras.CharactersByLora
$Characters = $CharacterLoras.Characters

$UnknownLoras = @{}

$Files = Get-ChildItem -Path $Path -File -Recurse:$Recurse
foreach ($File in $Files) {
    $FileNameParts = $File.Name | Select-String -Pattern '^(?:(.+)\s*)?([0-9]{14}[a-zA-Z0-9_]*)(.+)$'
    if (!$FileNameParts) {
        continue
    }

    $FileNamePrefix = $FileNameParts.Matches[0].Groups[1].Value
    $FileNameBase = $FileNameParts.Matches[0].Groups[2].Value
    $FileNameSuffix = $FileNameParts.Matches[0].Groups[3].Value

    if (!$Force -and $FileNamePrefix) {
        continue
    }

    if (!$FileNameBase) {
        continue
    }

    # Example:
    # Steps: 20, Sampler: DPM++ 2M SDE Karras, CFG scale: 7, Seed: 3461042217, Size: 512x768, Model hash: f22bb5699d, Model: MeinaHentai V5, VAE hash: 235745af8d, VAE: kl-f8-anime2.ckpt, Clip skip: 2, NGMS: 2, Lora hashes: "ostris's detail_slider_v4: 8347b7ec221e, chara_MushokuTensei_ErisBoreasGreyrat_v1: eba8be81e519", Eta: 0.667, Pad conds: True, Version: v1.7.0
    $FileHeader = $File | Get-Content -Encoding ascii -TotalCount 100

    $FileLoras = $FileHeader | Select-String -Pattern '(?s)<lora:([^>:]+)(?:\:([^>]+))?>(?: *,)? *\(?([^\r\n<:]+)' -AllMatches | % { $_.Matches } | % { 
        $Lora = $_.Groups[1].Value
        $Prompt = $_.Groups[3].Value
        $FileCharacters = $CharactersByLora[$Lora.ToLower()]

        if (@($FileCharacters).Length -eq 1) {
            $FileCharacter = $FileCharacters
        }
        else {
            $FileCharacter = $FileCharacters | Where-Object { $Prompt -imatch "\b$($_.TriggerWord)\b" }
        }

        @{ 
            Lora       = $Lora
            LoraWeight = $_.Groups[2].Value
            Prompt     = $Prompt
            Characters = $FileCharacters
            Character  = $FileCharacter
        }; 
    } | Where-Object {
        $_.Lora -notmatch "(\b|_)(mfcg|LUUNA|prgfrg23|reweik|slider)(\b|_)"
    }

    if ($FindCharacterByTrigger -and @($FileLoras | Where-Object { !!$_.Character }).Length -eq 0) {
        Write-Debug "File has no character loras, looking for characters by trigger words only"

        # Find characters not using lora (known by the base model) by trigger word only
        $FileLoras = $Characters `
        | Where-Object { !$_.Lora } `
        | % { 
            $FileCharacter = $_
            $Matches = $FileHeader | Select-String -Pattern "(?s)$([Regex]::Escape($FileCharacter.TriggerWord + ''))(?: *,)? *([^\r\n<]+)?" -AllMatches | % { $_.Matches }

            if (!$Matches) {
                return @{
                    IsMatch = $false
                };
            }

            return @{
                IsMatch    = $true
                Prompt     = $Matches[0].Groups[2].Value
                Characters = @($FileCharacter)
                Character  = $FileCharacter
            };
        } `
        | Where-Object { $_.IsMatch }
    }
    
    $FirstCharacter = $FileLoras | % { $_.Character } | Where-Object { !!$_ } | Select-Object -First 1
    $ModelName = $FileHeader | Select-String -Pattern '(?s)Model: ([^,\r\n]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
    $Seed = $FileHeader | Select-String -Pattern '(?s)Seed: ([^,\r\n]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
    $Prompts = ($FileHeader | Join-String -Separator "`n") -Split "`nNegative prompt:"

    $FirstFileLora = $FileLoras | Where-Object { !!$_.Character } | Select-Object -First 1
    if (!$FirstFileLora) {
        $FirstFileLora = $FileLoras | Select-Object -First 1
    }

    if ($FirstCharacter -or $IncludeNoCharacter) {
        $Series = $FirstCharacter.Series
        $Character = $FirstCharacter.Name
        $Author = $FirstCharacter.Author

        if ($FirstCharacter.Author) {
            $CharacterAndAuthor = "$Character by $Author"
        }
        else {
            $CharacterAndAuthor = $Character
        }

        $FoundKeywordValues = @{}
        foreach ($kvp in $KeywordMap.GetEnumerator()) {
            $Keyword = $kvp.Key
            $MappedValue = $kvp.Value

            if ($Prompts[0] -Match $Keyword) {
                $FoundKeywordValues[$MappedValue.ToLower()] = $MappedValue
            }
        }

        $FormatValues = @{
            series             = $Series
            character          = $Character
            author             = $Author
            characterandauthor = $CharacterAndAuthor
            modelname          = $ModelName
            seed               = $Seed
            filenamebase       = $FileNameBase
            filenamesuffix     = $FileNameSuffix
            keywords           = ($FoundKeywordValues.Values | Join-String -Separator ", ")
            epoch              = $FirstCharacter.Epoch
            steps              = $FirstCharacter.Steps
            lora               = $FirstFileLora.Lora
            prompt             = $FirstFileLora.Prompt
        }

        $NewName = $Format `
            -ireplace '\$([a-z]+)', { $FormatValues[$_.Groups[1].Value.ToLower()] ?? $_ } `
            -ireplace '(:|"|/|\\|\*|\?)', ''
        $NewName = $NewName.Trim()

        if ($SkipIfMissingKeyword -and $NewName.Contains("$")) {
            Write-Warning "$($File.FullName) > missing keyword value: $NewName"
            Write-Warning "Keywords available: $(ConvertTo-Json $FormatValues)"
        }
        else {
            $OriginalName = $File.Name
        
            if ($NewName -ine $OriginalName) {
                Write-Host "$($File.FullName) > $NewName"
    
                if (!$DryRun) {
                    $NewFullName = "$($File.Directory.FullName)\$NewName"
                    if ($Overwrite -and (Test-Path -LiteralPath $NewFullName)) {
                        Remove-Item $NewFullName
                    }

                    try {
                        Move-Item -LiteralPath $File.FullName -Destination $NewFullName
                    }
                    catch {
                        Write-Warning ("Failed to rename file: " + $_)
                    }
                }
            }
        }
    }
    else {
        if ($FileLoras | % { $_.Characters } | Select-Object -First 1) {
            Write-Warning "$($File.FullName) > missing character trigger word (one of: $($FileLoras | % { $_.Characters } | % { $_.TriggerWord } | Join-String -Separator ", "))"
        }
        else {
            Write-Warning "$($File.FullName) > unknown character (loras: $($FileLoras | % { $_.Lora } | Join-String -Separator ", "))"
        }

        $FileLoras | % { $_.Lora } | Where-Object { !!$_ } | % { $UnknownLoras[$_] = $_ }
    }
}

if ($UnknownLoras.Count -gt 0) {
    Write-Warning "List of unknown loras:`n$($UnknownLoras.Keys | Join-String -Separator "`n")"
}