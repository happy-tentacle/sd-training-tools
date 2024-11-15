param (
    [Parameter(Mandatory = $true)] [string[]] $CharacterPrompts,
    [Parameter(Mandatory = $false)] [string] $BasePromptPath,
    [Parameter(Mandatory = $false)] [string] $OutDir = "T:\stablediffusion\outputs",
    [Parameter(Mandatory = $false)] [Switch] $DryRun,
    [Parameter(Mandatory = $false)] [int] $BatchSize = 1,
    [Parameter(Mandatory = $false)] [int] $IterationsPerChar = 1,
    [Parameter(Mandatory = $false)] [int] $Iterations = 1,
    [Parameter(Mandatory = $false)] [int] $Seed = -1
)

# NOTE: Make sure to start webui with flag "--api"

$ErrorActionPreference = "Stop"

$Uri = "http://127.0.0.1:7860/sdapi/v1/txt2img"

$BasePrompt = Get-Content -Raw -Path $BasePromptPath
$NegativePrompt = $BasePrompt | Select-String -Pattern '(?s)Negative prompt: ([^\r\n]*)' | % { $_.Matches[0]?.Groups[1]?.Value }
$NegativePrompt = $NegativePrompt -ireplace '(?s)^([\r\n]+)|([\r\n]+)$'
$BasePrompt = $BasePrompt -ireplace '(?s)Negative prompt: (.*)$', ""
$BasePrompt = $BasePrompt -ireplace '(?s)^([\r\n]+)|([\r\n]+)$'

$ImageCount = $BatchSize * $IterationsPerChar
$CharCount = $CharacterPrompts.Length * $Iterations
$CharPosition = 1

for ($i = 0; $i -lt $Iterations; $i += 1) {
    foreach ($CharacterPrompt in $CharacterPrompts) {
        $GenerationPrompt = $BasePrompt -ireplace '# Character prompt here', $CharacterPrompt
    
        # See http://127.0.0.1:7860/docs#/default/text2imgapi_sdapi_v1_txt2img_post
        $Body = @{
            prompt                               = $GenerationPrompt
            negative_prompt                      = $NegativePrompt
            seed                                 = $Seed
            sampler_index                        = "Euler A SGMUniform"
            steps                                = 40
            cfg_scale                            = 7
            width                                = 768
            height                               = 1024
            eta                                  = 0.667
            denoising_strength                   = 0.5
            batch_size                           = $BatchSize
            n_iter                               = $IterationsPerChar
            enable_hr                            = $True
            hr_scale                             = 2
            hr_upscaler                          = "4x_foolhardy_Remacri"
            hr_second_pass_steps                 = 15
            send_images                          = $False
            save_images                          = $True
            # See http://127.0.0.1:7860/docs#/default/get_config_sdapi_v1_options_get
            override_settings_restore_afterwards = $True
            override_settings                    = @{
                sd_model_checkpoint      = "animeConfettiComrade_v2 [14c3c10fe2]"
                sd_vae                   = "Automatic"
                CLIP_stop_at_last_layers = 2
                img2img_extra_noise      = 0.1
                outdir_txt2img_samples   = $OutDir
                outdir_extras_samples    = $OutDir
                outdir_samples           = $OutDir
            }
        }
    
        Write-Host "[$CharPosition/$CharCount] - Generating $ImageCount image(s) for: $CharacterPrompt"
    
        if ($DryRun) {
            #Write-Host "POST $Uri"
            #$Body
        }
        else {
            Invoke-RestMethod -Method "Post" -Uri $Uri -Body ($Body | ConvertTo-Json) -ContentType "application/json"
        }
    
        $CharPosition += 1
    }
}