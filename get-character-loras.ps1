param (
    [Parameter(Mandatory = $false)] [bool] $IncludeTagFrequency = $True
)

$CharactersByLora = @{}
$Characters = Get-Content -Raw S:\h\sd\collection.md `
| Select-String -Pattern '(?s)```([^`]+)`' -AllMatches | % { $_.Matches } ` | % { $_.Groups[1]?.Value } `
| Select-String -Pattern '\| \(([^>:]+) - ([^:]+):0\)(?:[^<]*<lora:([^>:]+):([^>]+)>)?(?: *,)? *([^\r\n<]+)?' -AllMatches | % { $_.Matches } `
| % { @{ 
        Series      = $_.Groups[1].Value; 
        Name        = $_.Groups[2].Value -ireplace ' by ([^\)]+)';
        Lora        = $_.Groups[3].Value;
        LoraWeight  = $_.Groups[4].Value;
        Author      = $_.Groups[3].Value | Select-String -Pattern '^([^'']+)''s' | % { $_.Matches[0]?.Groups[1]?.Value }
        Prompt      = $_.Groups[5].Value;
        TriggerWord = $_.Groups[5].Value | Select-String -Pattern '^\(? *([^,:]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
    }; 
}

$Characters | % {
    $Key = $_.Lora.ToLower()
    if (!$Key) {
        return
    }

    $ExistingValue = $CharactersByLora[$Key]
    if ($ExistingValue -and $ExistingValue -ne $_) {
        $Value = $($ExistingValue; $_)
    }
    else {
        $Value = $_
    }

    $CharactersByLora[$Key] = $Value
}

$Characters | % {
    $Key = ($_.Lora -ireplace "^([^'>]+'s )").ToLower()
    if (!$Key) {
        return
    }

    $ExistingValue = $CharactersByLora[$Key]
    if ($ExistingValue -and $ExistingValue -ne $_) {
        $Value = $($ExistingValue; $_)
    }
    else {
        $Value = $_
    }

    $CharactersByLora[$Key] = $Value
}

$LoraMetadata = Get-ChildItem -File -Filter *.safetensors -Path C:\tools\stable-diffusion-webui-reForge\models\Lora\characters | % {
    $RawMetadata = $_ | Get-Content -Encoding ascii -TotalCount 2
    $OutputName = $RawMetadata | Select-String -Pattern '"ss_output_name"\s*:\s*"([^"]+)"' | % { $_.Matches } | % { $_.Groups[1].Value }
    if ($OutputName -eq "None" -or $OutputName -eq "lora") {
        $OutputName = $Null
    }
    $Epoch = $RawMetadata | Select-String -Pattern '"ss_epoch"\s*:\s*"([^"]+)"' | % { $_.Matches } | % { $_.Groups[1].Value }
    $Steps = $RawMetadata | Select-String -Pattern '"ss_steps"\s*:\s*"([^"]+)"' | % { $_.Matches } | % { $_.Groups[1].Value }

    if ($IncludeTagFrequency) {
        try {
            $TagFrequency = $RawMetadata `
            | Select-String -Pattern '"ss_tag_frequency":"((?:\\"|[^"])+)"' `
            | % { $_.Matches } | % { $_.Groups[1].Value -ireplace '\\"', '"' -ireplace '\\\\', '\\' -ireplace '\\"', '"' } `
            | ConvertFrom-Json
            | % { $_.dataset }
        }
        catch {
            Write-Error "Error parsing raw metadata`n$($RawMetadata | Select-String -Pattern '"ss_tag_frequency":"((?:\\"|[^"])+)"' | % { $_.Matches } | % { $_.Groups[1].Value -ireplace '\\\\', '\\' -ireplace '\\"', '"' })"
            throw $_
        }
    }

    @{ 
        Path         = $_.FullName
        FileName     = $_.BaseName
        OutputName   = $OutputName
        TagFrequency = $TagFrequency
        Epoch        = $Epoch
        Steps        = $Steps
        Author       = $_.Name | Select-String -Pattern '([^''>]+)' | % { $_.Matches[0]?.Groups[1]?.Value }
    }
}

foreach ($Item in $LoraMetadata) {
    if (!$Item.FileName) {
        continue
    }

    $Value = $CharactersByLora[$Item.FileName.ToLower()]

    if ($Item.OutputName) {
        if ($Value) {
            $CharactersByLora[$Item.OutputName.ToLower()] = $Value
        }
        else {
            $Value = $CharactersByLora[$Item.OutputName.ToLower()]
            if ($Value) {
                $CharactersByLora[$Item.FileName.ToLower()] = $Value
            }
        }
    }

    if (!$Value) {
        $Value = @{ 
            Lora       = $Item.FileName;
            LoraWeight = 1;
        }   
    }

    if ($Value) {
        if (@($Value).Length -gt 1) {
            if ($Value | Where-Object { $_.Author -ieq $Item.Author } | Select-Object -First 1) {
                $Value = $Value | Where-Object { $_.Author -ieq $Item.Author }
            }
            elseif ($Value | Where-Object { $_.Lora -eq $Item.FileName } | Select-Object -First 1) {
                $Value = $Value | Where-Object { $_.Lora -eq $Item.FileName }
            }
        }

        $Value | % {
            if ($Item.Author) {
                $_.Author = $Item.Author
            }

            $_.OutputName = $Item.OutputName
            $_.FileName = $Item.FileName
            $_.TagFrequency = $Item.TagFrequency
            $_.Epoch = $Item.Epoch
            $_.Steps = $Item.Steps
        }

        $CharactersByLora[($Item.FileName -ireplace "^([^'>]+'s )").ToLower()] = $Value
    }
}

return @{
    Characters       = $Characters
    CharactersByLora = $CharactersByLora
    LoraMetadata     = $LoraMetadata
}