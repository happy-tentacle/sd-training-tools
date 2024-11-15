param (
    [Parameter(Mandatory = $true)] [string] $Path
)

$ErrorActionPreference = "Stop"

$CharacterLoras = & "$PSScriptRoot\get-character-loras.ps1"
$CharactersByLora = $CharacterLoras.CharactersByLora
$Characters = $CharacterLoras.Characters

$FilesMetadata = Get-ChildItem -Path $Path -File | % {
    $File = $_
    $FileNameParts = $File.Name | Select-String -Pattern '^(.+)?([0-9]{14}[a-zA-Z0-9_]*)(.+)$'
    if (!$FileNameParts) {
        return
    }

    $FileNamePrefix = $FileNameParts.Matches[0].Groups[1].Value
    $FileNameBase = $FileNameParts.Matches[0].Groups[2].Value
    $FileNameSuffix = $FileNameParts.Matches[0].Groups[3].Value

    if (!$FileNameBase) {
        return
    }

    return @{
        File           = $File
        FileNamePrefix = $FileNamePrefix
        FileNameBase   = $FileNameBase
        FileNameSuffix = $FileNameSuffix
    }
} | Where-Object { !!$_.FileNameBase }

foreach ($FileMetadata in $FilesMetadata) {
    $File = $FileMetadata.File
    # Example:
    # Steps: 20, Sampler: DPM++ 2M SDE Karras, CFG scale: 7, Seed: 3461042217, Size: 512x768, Model hash: f22bb5699d, Model: MeinaHentai V5, VAE hash: 235745af8d, VAE: kl-f8-anime2.ckpt, Clip skip: 2, NGMS: 2, Lora hashes: "ostris's detail_slider_v4: 8347b7ec221e, chara_MushokuTensei_ErisBoreasGreyrat_v1: eba8be81e519", Eta: 0.667, Pad conds: True, Version: v1.7.0
    $FileHeader = $File | Get-Content -Encoding ascii -TotalCount 40

    $FileLoras = $FileHeader `
    | Select-String -Pattern '(?s)<lora:([^>:]+):([^>]+)>(?: *,)? *([^\r\n<]+)' -AllMatches | % { $_.Matches } `
    | % { 
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
    }

    if (@($FileLoras | Where-Object { !!$_.Character }).Length -eq 0) {
        Write-Debug "File has no character loras, looking for characters by trigger words only"

        # Find characters not using lora (known by the base model) by trigger word only
        $FileLoras = $Characters `
        | Where-Object { !$_.Lora } `
        | % { 
            $FileCharacter = $_
            $Matches = $FileHeader | Select-String -Pattern "(?s)$([Regex]::Escape($FileCharacter.TriggerWord))(?: *,)? *([^\r\n<]+)?" -AllMatches | % { $_.Matches }

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
    
    $FileMetadata.Prompt = $FileHeader | Join-String -Separator "`n" | Select-String -Pattern "(?s)EXtparameters.(.+)\nNegative prompt\:" -AllMatches | % { $_.Matches[0]?.Groups[1]?.Value?.Trim() }
    $FileMetadata.FirstCharacter = $FileLoras | % { $_.Character } | Where-Object { !!$_ } | Select-Object -First 1
    $FileMetadata.ModelName = $FileHeader | Select-String -Pattern '(?s)Model: ([^,\r\n]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
    $FileMetadata.Seed = $FileHeader | Select-String -Pattern '(?s)Seed: ([^,\r\n]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
}

return @{
    CharacterLoras = $CharacterLoras
    FilesMetadata  = $FilesMetadata
}