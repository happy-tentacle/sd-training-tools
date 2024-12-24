param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $false)] [string] $OutputDir,
    [Parameter(Mandatory = $false)] [string] $BlendSourceDir,
    [Parameter(Mandatory = $false)] [string] $BlendValue,
    [Parameter(Mandatory = $false)] [string] $Extension,
    [Parameter(Mandatory = $false)] [string] $Colorspace, # rgb, sRGB, cmyk, etc (see https://imagemagick.org/script/command-line-options.php?#colorspace)
    [Parameter(Mandatory = $false)] [string] $ResizeTo,
    [Parameter(Mandatory = $false)] [switch] $Normalize,
    [Parameter(Mandatory = $false)] [switch] $Recurse,
    [Parameter(Mandatory = $false)] [switch] $DeleteOriginal,
    [Parameter(Mandatory = $false)] [switch] $Force,
    [Parameter(Mandatory = $false)] [switch] $DryRun
)

$ErrorActionPreference = "Stop"

$FileList = Get-ChildItem -File -Recurse:$Recurse -LiteralPath $Path | Where-Object { $Force -or !$Extension -or !$_.Name.EndsWith($Extension) -and ($_.Name -match "\.(png|jpg|jpeg|bmp|gif|webp)$") }

if (!$OutputDir) {
    $OutputDir = "$Path\converted"
}

if ($OutputDir -and !(Test-Path -LiteralPath $OutputDir)) {
    [void](New-Item -Force -ItemType Directory -Path $OutputDir)
}

foreach ($File in $FileList) {
    $NewExtension = $Extension ? $Extension : $File.Extension
    $NewFullName = "$OutputDir\$($File.BaseName)$NewExtension"
    
    $MagickArgs = [System.Collections.ArrayList]@()

    if ($BlendSourceDir -and $BlendValue -gt 0) {
        $BlendImage = "$($BlendSourceDir)\$($File.Name)"
        if (!(Test-Path -LiteralPath $BlendImage)) {
            Write-Warning "Could not find blend source image ""$BlendImage"""
        }
        else {
            [void]$MagickArgs.Add("composite")
            [void]$MagickArgs.Add("-blend")
            [void]$MagickArgs.Add($BlendValue)
            [void]$MagickArgs.Add("-gravity")
            [void]$MagickArgs.Add("Center")
            [void]$MagickArgs.Add($BlendImage)
        }
    }
    
    [void]$MagickArgs.Add($File.FullName)

    if ($ResizeTo -gt 0) {
        [void]$MagickArgs.Add("-resize")
        [void]$MagickArgs.Add($ResizeTo)
    }

    if ($Normalize) {
        [void]$MagickArgs.Add("-contrast-stretch")
        [void]$MagickArgs.Add("0.5%x0.5%")
    }

    if ($Colorspace) {
        [void]$MagickArgs.Add("-colorspace")
        [void]$MagickArgs.Add($Colorspace)
    }

    [void]$MagickArgs.Add($NewFullName)
    
    Write-Host "magick $MagickArgs"
    if (!$DryRun) {
        & magick $MagickArgs
        if ($LASTEXITCODE -ne 0) {
            exit 1
        }
    }

    if ($DeleteOriginal) {
        Write-Host "Deleting original file ""$($File.Fullname)"""
        if (!$DryRun) {
            Remove-Item -LiteralPath ($File.Fullname)
        }
    }
}