param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $false)] [string] $TrainingBasePath = "~/dev/training",
    [Parameter(Mandatory = $false)] [string] $ModelPath = "$TrainingBasePath/ponyDiffusionV6XL_v6StartWithThisOne.safetensors",
    [Parameter(Mandatory = $false)] [string] $LoraFilePrefix = "happy_tentacle-",
    [Parameter(Mandatory = $false)] [string] $Trigger = "",
    [Parameter(Mandatory = $false)] [int] $Repeats = 0,
    [Parameter(Mandatory = $false)] [int] $MaxSteps = 1400,
    [Parameter(Mandatory = $false)] [int] $BatchSize = 3,
    [Parameter(Mandatory = $false)] [int] $TargetEpochs = 10,
    [Parameter(Mandatory = $false)] [switch] $Overwrite,
    [Parameter(Mandatory = $false)] [double] $WeightDecay = 0.05,
    [Parameter(Mandatory = $false)] [double] $DCoef = 1
)

$ErrorActionPreference = "Stop"

$TagFiles = .\get-file-tags.ps1 -Path $Path -Recurse | Where-Object { $_.File.Directory.Name -notmatch "^_" }
$Directories = $TagFiles | % { $_.File.Directory } | Get-Unique

if (!$Trigger) {
    $Trigger = $TagFiles | `
        % { $_.Tags } | Group-Object | Sort-Object -Descending -Property "Count" | `
        Where-Object { $_.Name -notmatch "^(looking)\b|\b(1girl|solo|eyes|hair|smile|background|comic|monochrome|greyscale|shot|indoors|outdoors|blush)$" } | `
        Select-Object -First 1 | % { $_.Name }
    if (!$Trigger) {
        Write-Error "No trigger could be found"
        exit 1
    }

    Write-Warning "No trigger specified, will autoselect trigger from file tags"
}

if (!$Repeats) {
    $Repeats = [Math]::Ceiling([double]$MaxSteps / $TargetEpochs / ([double]@($TagFiles).Count / $BatchSize))
}

$RootDirectory = Get-Item -LiteralPath $Path
$RootDirectoryName = $RootDirectory.Name
$LoraFileName = "$LoraFilePrefix$RootDirectoryName"

Write-Host "TargetEpochs: $TargetEpochs"
Write-Host "MaxSteps: $MaxSteps"
Write-Host "BatchSize: $BatchSize"
Write-Host "Trigger: $Trigger"
Write-Host "LoraFileName: $LoraFileName"
Write-Host "WeightDecay: $WeightDecay"
Write-Host "DCoef: $DCoef"

$DirRepeats = $Directories | % { 
    $Dir = $_
    $DirRepeats = $Dir.Name | Select-String -Pattern "(?:^|_| )x([0-9]+)" | % { $_.Matches.Groups[1].Value }
    if (!$DirRepeats) {
        $DirRepeats = 1
    }
    $DirTagFiles = @($TagFiles | Where-Object { $_.File.Directory.FullName -eq $Dir.FullName })
    @{
        Dir                  = $Dir
        TagFiles             = $DirTagFiles
        Repeats              = $DirRepeats
        FileCountWithRepeats = $DirTagFiles.Count * $DirRepeats
    }
}

$RawFileCountWithRepeats = ($DirRepeats | % { $_.FileCountWithRepeats } | Measure-Object -Sum).Sum
Write-Host "RawFileCountWithRepeats = $RawFileCountWithRepeats"

$TargetFileCount = [int][Math]::Ceiling([double]$MaxSteps * $BatchSize / $TargetEpochs)
Write-Host "TargetFileCount = $TargetFileCount"



$Subsets = ($DirRepeats | % {
        $Dir = $_.Dir
        $RelativeDirPath = Resolve-Path -Relative -LiteralPath $Dir.FullName -RelativeBasePath $Path

        $TotalRepeats = $_.Repeats
        $TotalRepeats = [int][Math]::Round([double]$_.FileCountWithRepeats * $TargetFileCount / $RawFileCountWithRepeats / $_.TagFiles.Count)
        
        Write-Host "Directory ""$($Dir.Name)"" FileCount=$($_.TagFiles.Count) Repeat=$TotalRepeats"

        "[[subsets]]
caption_extension = "".txt""
image_dir = ""$((Join-Path $TrainingBasePath $RootDirectoryName ($RelativeDirPath.Trim("."))).Replace("\", "/"))""
keep_tokens = 1
name = ""$($Dir.Name)""
num_repeats = $TotalRepeats
shuffle_caption = true"
    }) -Join "`n`n"

$Settings = 
"$Subsets

[train_mode]
train_mode = ""lora""

[general_args.args]
max_data_loader_n_workers = 1
persistent_data_loader_workers = true
pretrained_model_name_or_path = ""$ModelPath""
sdxl = true
no_half_vae = true
mixed_precision = ""fp16""
gradient_checkpointing = true
gradient_accumulation_steps = 1
seed = 0
max_token_length = 225
prior_loss_weight = 1.0
xformers = true
max_train_steps = $MaxSteps
cache_latents = true

[general_args.dataset_args]
resolution = [ 1024, 1024,]
batch_size = $BatchSize

[network_args.args]
network_dim = 8
network_alpha = 8.0
min_timestep = 0
max_timestep = 1000
network_dropout = 0.1

[optimizer_args.args]
optimizer_type = ""Prodigy""
lr_scheduler = ""cosine""
loss_type = ""l2""
learning_rate = 1.0
unet_lr = 1.0
text_encoder_lr = 1.0
max_grad_norm = 1.0
scale_weight_norms = 1.0
min_snr_gamma = 5
warmup_ratio = 0.01

[saving_args.args]
output_dir = ""$TrainingBasePath/$RootDirectoryName""
output_name = ""$LoraFileName""
save_precision = ""fp16""
save_model_as = ""safetensors""
save_every_n_epochs = 1
save_toml = true
save_last_n_epochs_state = 1
save_state = true

[sample_args.args]
sample_sampler = ""euler_a""
sample_every_n_epochs = 1
sample_prompts = ""$TrainingBasePath/$RootDirectoryName/test-prompt.txt""

[bucket_args.dataset_args]
enable_bucket = true
min_bucket_reso = 256
max_bucket_reso = 2048
bucket_reso_steps = 64

[network_args.args.network_args]

[optimizer_args.args.optimizer_args]
d_coef = ""$DCoef""
weight_decay = ""$WeightDecay""
decouple = ""True""
betas = ""0.9,0.99""
use_bias_correction = ""True""
safeguard_warmup = ""True""
"

$TestPrompt = 
"$Trigger, 1girl, solo, smile, cowboy shot, looking at viewer, outdoors, score_9, score_8_up, score_7_up, score_6_up, score_5_up, score_4_up --n simple background, out of frame
$Trigger, school uniform, 1girl, solo, smile, cowboy shot, looking at viewer, outdoors, score_9, score_8_up, score_7_up, score_6_up, score_5_up, score_4_up --n simple background, out of frame
$Trigger, kimono, 1girl, solo, smile, cowboy shot, looking at viewer, outdoors, score_9, score_8_up, score_7_up, score_6_up, score_5_up, score_4_up --n simple background, out of frame
$Trigger, bikini, 1girl, solo, smile, cowboy shot, looking at viewer, outdoors, score_9, score_8_up, score_7_up, score_6_up, score_5_up, score_4_up --n simple background, out of frame"

if ($Overwrite -or !(Test-Path -LiteralPath "$Path\settings.toml")) {
    Set-Content -NoNewline -LiteralPath "$Path\settings.toml" -Value $Settings
}
else {
    Write-Warning """$Path\settings.toml"" already exists and will not be overwritten"
}

if ($Overwrite -or !(Test-Path -LiteralPath "$Path\test-prompt.txt")) {
    Set-Content -NoNewline -LiteralPath "$Path\test-prompt.txt" -Value $TestPrompt
}
else {
    Write-Warning """$Path\test-prompt.txt"" already exists and will not be overwritten"
}