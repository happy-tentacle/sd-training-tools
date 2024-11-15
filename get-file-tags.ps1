param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $false)] [switch] $Recurse,
    [Parameter(Mandatory = $false)] [switch] $ProcessMultiline,
    [Parameter(Mandatory = $false)] [switch] $DryRun
)

$ErrorActionPreference = "Stop"

$FileList = Get-ChildItem -File -Recurse:$Recurse -LiteralPath $Path -Filter "*.txt" | Where-Object { $_.FullName -notmatch "\\\..*" }
$TagFiles = [System.Collections.ArrayList]@()

foreach ($File in $FileList) {
    $FileContent = $File | Get-Content -Raw

    if (!$ProcessMultiline -and $FileContent.Contains("`n")) {
        continue
    }

    $FileTags = [System.Collections.Generic.List[String]]@()
    $FileTagsSet = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)

    function Add-Tag {
        Param (
            [switch] $Prepend,
            [switch] $IgnoreStats
        )
        Process {
            foreach ($Tag in @(($_ ?? "").Split(", ") | % { $_.Trim().ToLowerInvariant() })) {
                if ($Tag -and ($Prepend -or !$FileTagsSet.Contains($Tag))) {
                    $FileTags.Add($Tag) | Out-Null
                    $FileTagsSet.Add($Tag) | Out-Null
                }
            }
        }
    }

    ($FileContent ?? "").Split(", ") | Add-Tag -IgnoreStats
    
    $TagFiles.Add(@{
            File = $File
            Tags = $FileTags
        }) | Out-Null

}

$TagFiles
