# Example usage:
# > clear && T:\tools\lora-training\process-tags.ps1 -SortTagsByCount -KeepTags 1 -LogTags -LogFolderName -LogStats -Recurse -Path "..."

param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $false)] [string[]] $AddTags, # Also supports removing tags via syntax "-tag"
    [Parameter(Mandatory = $false)] [string[]] $RemoveTags,
    [Parameter(Mandatory = $false)] [string[]] $FindTags,
    [Parameter(Mandatory = $false)] [string[]] $ReplaceTags, # Syntax: "OldTag:NewTag"
    [Parameter(Mandatory = $false)] [string[]] $PrependTags,
    [Parameter(Mandatory = $false)] [switch] $RunTagger,
    [Parameter(Mandatory = $false)] [switch] $TagFolderName, # NOTE: TagFolderName is applied before files are reorganized with OrganizeFilesBy
    [Parameter(Mandatory = $false)] [switch] $LogFileName,
    [Parameter(Mandatory = $false)] [switch] $LogFolderName,
    [Parameter(Mandatory = $false)] [switch] $LogTags,
    [Parameter(Mandatory = $false)] [switch] $LogStats,
    [Parameter(Mandatory = $false)] [switch] $Recurse,
    [Parameter(Mandatory = $false)] [switch] $SortTagsByCount,
    [Parameter(Mandatory = $false)] [switch] $RemoveRedundantTags,
    [Parameter(Mandatory = $false)] [switch] $RemoveUnwantedTags,
    [Parameter(Mandatory = $false)] [string] $OrganizeFilesBy,
    [Parameter(Mandatory = $false)] [switch] $SuffixFileCount,
    [Parameter(Mandatory = $false)] [switch] $ProcessMultiline,
    [Parameter(Mandatory = $false)] [int] $KeepTags = 0,
    [Parameter(Mandatory = $false)] [switch] $DryRun,
    [Parameter(Mandatory = $false)] [switch] $Preset1
)

$ErrorActionPreference = "Stop"

if ($Preset1) {
    $LogFolderName = $True
    $LogTags = $True
    $LogStats = $True
    $RemoveRedundantTags = $True
    $RemoveUnwantedTags = $True
    $SortTagsByCount = $True
    if ($KeepTags -eq 0) {
        $KeepTags = 1 # Keep trigger word
    }
}

if ($RunTagger) {
    $TaggerCommand = "python $PSScriptRoot\process.py --input-type image --output-meta txt --tag-only --input ""$Path"" --output ""$Path"" $($Recurse ? '--recursive' : '')"
    Write-Host $TaggerCommand
    Invoke-Expression $TaggerCommand
    if ($LASTEXITCODE -ne 0) {
        exit 1
    }

    $TxtFiles = Get-ChildItem -File -LiteralPath $Path -Filter "*.txt"
    $ImgFiles = Get-ChildItem -File -LiteralPath $Path -Recurse:$Recurse | Where-Object { $_.Name -match "\.(png|jpg|jpeg|bmp|gif|webp)$" }
    foreach ($TxtFile in $TxtFiles) {
        $ImgFile = $ImgFiles | Where-Object { $_.BaseName -eq $TxtFile.BaseName }
        if ($ImgFile -and $ImgFile.Directory.FullName -ne $TxtFile.Directory.FullName) {
            Move-Item -LiteralPath ($TxtFile.FullName) -Destination "$($ImgFile.Directory.FullName)\$($TxtFile.Name)"
        }
    }
}

if ($KeepTags -eq 0 -and $PrependTags) {
    $KeepTags = $PrependTags.Count
}

# Settings

$UntaggedLabel = "_none"
$TagScoreThreshold = 0.65

# Build config

$Config = Get-Content -Raw -LiteralPath "$($PSScriptRoot)\process-tags.config.jsonc" | ConvertFrom-Json

$TagsByCategory = [System.Collections.Generic.Dictionary[String, System.Collections.Specialized.OrderedDictionary]]::new([StringComparer]::InvariantCultureIgnoreCase)
$Config.tagCategories | % { 
    # Category tags stored in a SortedSet by descending priority
    $Dict = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::InvariantCultureIgnoreCase)
    $_.tags | % { $Dict.Add($_, $_) }
    $TagsByCategory.Add($_.name, $Dict)
}

$RedundantTags = [System.Collections.Generic.Dictionary[String, String]]::new([StringComparer]::InvariantCultureIgnoreCase)
$Config.redundantTags | get-member -type properties | % { 
    $RedundantTags.Add($_.Name, ($Config.redundantTags | Select-Object -ExpandProperty $_.Name))
}

$TagsToKeep = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
$TagsToKeep.UnionWith([string[]]@($Config.tagsToKeep))
$TagsToKeep.UnionWith([string[]]@($TagsByCategory.Values | % { $_.Keys }))

$TagsWithoutColor = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
$TagsWithoutColor.UnionWith([string[]]@($Config.tagsWithoutColor))

$TagsToWarn = [System.Collections.Generic.Dictionary[String, double]]::new([StringComparer]::InvariantCultureIgnoreCase)
$Config.tagsToWarn | get-member -type properties | % { 
    $TagsToWarn.Add($_.Name, ($Config.tagsToWarn | Select-Object -ExpandProperty $_.Name))
}

$UnwantedTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
$UnwantedTags.UnionWith([string[]]@($Config.unwantedTags))

$BooruTagsFilePath = "$($PSScriptRoot)\danbooru-tags-500+.csv"
if (Test-Path $BooruTagsFilePath) {
    $BooruTags = Get-Content -Raw $BooruTagsFilePath | ConvertFrom-Csv | % { @{ name = $_.name; post_count = [int]$_.post_count } }
}
else {
    # Taken from https://old.reddit.com/r/comfyui/comments/1amo41u/updated_danbooru_tag_list_and_counts_for/
    $BooruTagsCsv = (Invoke-WebRequest "https://gist.githubusercontent.com/bem13/0bc5091819f0594c53f0d96972c8b6ff/raw/b0aacd5ea4634ed4a9f320d344cc1fe81a60db5a/danbooru_tags_post_count.csv").Content
    $BooruTags = $BooruTagsCsv | ConvertFrom-Csv -Header @("name", "post_count") | % { @{ name = $_.name.Replace("_", " "); post_count = [int]$_.post_count } } | Where-Object { $_.post_count -ge 500 }
    $BooruTags | ConvertTo-Csv | Set-Content -LiteralPath $BooruTagsFilePath
}

$KnownBooruTags = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::InvariantCultureIgnoreCase)
$BooruTags | % { $KnownBooruTags[$_.name.Replace("(", "\(").Replace(")", "\)")] = $_.post_count }

# Parse options

$PathDirectory = Get-Item -LiteralPath $Path.TrimEnd("\")
$FileList = Get-ChildItem -File -Recurse:$Recurse -LiteralPath $Path -Filter "*.txt" | Where-Object { $_.FullName -notmatch "\\\..*" }
$FileDirs = $FileList | % { $_.Directory } | Get-Unique
$FileDirImages = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
$FileDirImages.UnionWith([string[]]@($FileDirs | % { Get-ChildItem -File -LiteralPath $_.FullName } | % { $_.FullName } | % { $_ | Select-String -Pattern "^(.+)\.(png|jpg|jpeg|bmp|gif|webp)$" } | % { $_.Matches.Groups[1] }))
# Exclude txt files that have no corresponding image
$FileList = $FileList | Where-Object { $FileDirImages.Contains(($_.FullName | Select-String -Pattern "^(.+)\.txt$" | % { $_.Matches.Groups[1] })) }

# Statistics

$FileCount = @($FileList).Count
$FileCountString = $FileCount.ToString()
$CountByTags = [System.Collections.Generic.Dictionary[String, int]]::new([StringComparer]::InvariantCultureIgnoreCase)
$TagFiles = [System.Collections.ArrayList]@()

$FindTagsSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
$FindTagsSet.UnionWith([string[]]@($FindTags | % { ($_ ?? "").Split(",") } | % { $_.Trim().ToLowerInvariant() }))

$CategoryScores = [System.Collections.ArrayList]@()

# Helper functions
    
function Get-Files-By-Category {
    param (
        [Parameter(Mandatory = $true)] [string] $CategoryName,
        [Parameter(Mandatory = $false)] [switch] $IncludePrefixes,
        [Parameter(Mandatory = $false)] [switch] $ExactMatch
    )

    $CategoryTags = $TagsByCategory[$CategoryName].Keys
    if (!$CategoryTags) {
        $CategoryTags = @($CategoryName.Split(",") | % { $_.Trim().ToLowerInvariant() })

        foreach ($Tag in $CategoryTags) {
            if ($Tag.Contains("*") -or $Tag.Contains("?")) {
                $CategoryTags += ($CountByTags.Keys | Where-Object { $_ -ilike $Tag })
            }
        }
    }

    if ($CategoryName -eq "clothing" -and $IncludePrefixes) {
        $TagsWithColor = $CategoryTags | % { $Tag = $_; $Config.clothingColors | % { "$_ $Tag" } }
        $TagsWithStyle = $CategoryTags | % { $Tag = $_; $Config.clothingStyles | % { "$_ $Tag" } }
        $CategoryTags += $TagsWithStyle + $TagsWithColor 
    }

    $Categorized = @($CategoryTags | % { $CategoryTag = $_; @{ 
                Category = $CategoryTag; 
                TagFiles = @($TagFiles | Where-Object { 
                        foreach ($Tag in $_.Tags) {
                            if ($ExactMatch) {
                                if ($Tag -ieq $CategoryTag) {
                                    return $true
                                }
                            }
                            else {
                                if ($Tag -match "\b$([Regex]::Escape($CategoryTag))\b") {
                                    return $true
                                }
                            }
                        }
                    }) 
            } 
        })

    $CategorizedFiles = [System.Collections.Generic.HashSet[object]]::new(@($Categorized | % { $_.TagFiles }))
    $Uncategorized = @{ 
        Category = $UntaggedLabel; 
        TagFiles = @($TagFiles | Where-Object { !$CategorizedFiles.Contains($_) }) 
    }

    $All = $Categorized + $Uncategorized
    $All | % { $_.FileCount = $_.TagFiles.Count }

    return $All
}

function Write-Tag-Category-Stats {
    param (
        [Parameter(Mandatory = $true)] [string] $CategoryName,
        [Parameter(Mandatory = $true)] [switch] $Silent
    )
    
    $FilesByCategory = Get-Files-By-Category -CategoryName $CategoryName
    $FilesWithoutTags = ($FilesByCategory | Where-Object { $_.Category -eq $UntaggedLabel } | % { $_.TagFiles })

    if (!$Silent) {
        Write-Host "--  Files by $($CategoryName):  ".PadRight(80, "-")
    
        $Index = 0
        foreach ($CategoryFiles in ($FilesByCategory | Where-Object { $_.Category -ne $UntaggedLabel -and $_.FileCount -gt 0 } | Sort-Object -Property FileCount -Descending)) {
            if ($Index -gt 0) {
                Write-Host ", " -NoNewline
            }
            Write-Host "$($CategoryFiles.Category): " -NoNewline
            Write-Host "$($CategoryFiles.TagFiles.Count)" -ForegroundColor Green -NoNewline
            $Index++
        }
    
        $CategoriesWithoutFiles = $FilesByCategory | Where-Object { $_.TagFiles.Count -eq 0 -and $_.Category -ne $UntaggedLabel }
        foreach ($Item in $CategoriesWithoutFiles) {
            if ($Index -gt 0) {
                Write-Host ", " -NoNewline
            }
            Write-Host "$($Item.Category): 0" -NoNewline
            $Index++
        }

        if ($FilesWithoutTags.Count -gt 0) {
            if ($Index -gt 0) {
                Write-Host ", " -NoNewline
            }
            Write-Host "none: " -NoNewline
            Write-Host "$($FilesWithoutTags.Count)" -ForegroundColor Red -NoNewline
        }
    
        Write-Host "" # New line
    }

    [void]$CategoryScores.Add(@{
            Category = $CategoryName
            Score    = $TagFiles.Count -gt 0 ? (($TagFiles.Count - $FilesWithoutTags.Count) / $TagFiles.Count) : 0
        })

    if ($LogFileName) {
        foreach ($TagFile in $FilesWithoutTags) {
            Write-Host (Resolve-Path -LiteralPath $TagFile.File.FullName -Relative -RelativeBasePath $Path ) -ForegroundColor Red
        }
    }
}

function Move-By-Category {
    param (
        [Parameter(Mandatory = $true)] [string] $CategoryName
    )

    $FilesByCategory = Get-Files-By-Category -CategoryName $CategoryName -IncludePrefixes -ExactMatch
    $FilesWithCategories = $TagFiles | % { $TagFile = $_; @{ TagFile = $TagFile; Categories = @($FilesByCategory | Where-Object { $_.Category -ne $UntaggedLabel -and $_.TagFiles.Contains($TagFile) }) } }

    foreach ($FileWithCategories in $FilesWithCategories) {
        $TagFile = $FileWithCategories.TagFile
        $Categories = $FileWithCategories.Categories
        $JoinedCategories = ($Categories | % { $_.Category.Replace("\)", ")").Replace("\(", "(") }) -Join ", "
        $Directory = $Categories.Count -eq 0 ? (Get-Item -LiteralPath $Path) : (New-Item -Force -ItemType Directory -Path "$Path\$JoinedCategories")
        $PrevFile = $TagFile.File

        $TagFile.File = Move-Item -PassThru -LiteralPath $TagFile.File.FullName -Destination "$Directory\"
        $TagFile.Directory = $Directory

        # Move associated files (i.e. image files with same name as tag files)
        $EscapedFilter = [Management.Automation.WildcardPattern]::Escape([Management.Automation.WildcardPattern]::Escape($PrevFile.Directory.FullName + "\" + $PrevFile.BaseName)) + ".*"
        Move-Item -Path $EscapedFilter -Destination "$Directory\" -Exclude "*.txt"
    }

    # Remove empty directories recursively
    # Adapted from https://stackoverflow.com/a/54619752
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory | `
        Select-Object -ExpandProperty FullName | `
        Sort-Object -Descending | `
        Where-Object { @($_ | Get-ChildItem -Force | Select-Object -First 1).Count -eq 0 } | `
        Remove-Item
}

# Main logic

foreach ($File in $FileList) {
    $FileContent = $File | Get-Content -Raw

    if (!$ProcessMultiline -and $FileContent.Contains("`n")) {
        continue
    }

    $FileTags = [System.Collections.Generic.List[String]]@()
    $FileTagsSet = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsAdded = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsRemoved = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)

    function Add-Tag {
        Param (
            [switch] $Prepend,
            [switch] $IgnoreStats
        )
        Process {
            foreach ($Tag in @(($_ ?? "").Split(",") | % { $_.Trim().ToLowerInvariant().Replace(")", "\)").Replace("(", "\(").Replace("\\", "\") })) {
                if ($Tag.StartsWith("-")) {
                    $Tag.Substring(1) | Remove-Tag
                }
                elseif ($Tag -and ($Prepend -or !$FileTagsSet.Contains($Tag))) {
                    if ($Prepend) {
                        [void]$FileTags.Remove($Tag)
                        [void]$FileTags.Insert(0, $Tag)
                    }
                    else {
                        [void]$FileTags.Add($Tag)
                    }
    
                    [void]$FileTagsSet.Add($Tag)
                    if (!$IgnoreStats) {
                        [void]$TagsAdded.Add($Tag)
                    }
                }
            }
        }
    }

    function Remove-Tag {
        Process {
            foreach ($Tag in @(($_ ?? "").Split(",") | % { $_.Trim().ToLowerInvariant().Replace(")", "\)").Replace("(", "\(").Replace("\\", "\") })) {
                if ($Tag -and $FileTagsSet.Contains($Tag)) {
                    [void]$FileTags.Remove($Tag)
                    [void]$FileTagsSet.Remove($Tag)
                    [void]$TagsRemoved.Add($Tag)
                }
            }
        }
    }

    ($FileContent ?? "") | Add-Tag -IgnoreStats
    $PrependTags | Add-Tag -Prepend
    $AddTags | Add-Tag

    if ($TagFolderName -and !$File.Directory.Name.StartsWith("_") -and $File.Directory.FullName -ne $PathDirectory.FullName) {
        $DirSep = [System.IO.Path]::DirectorySeparatorChar
        $DirName = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath ($File.FullName) -Relative -RelativeBasePath ($PathDirectory.FullName)))
        $DirName.Trim("." + $DirSep).Split($DirSep) | Select-String -Pattern "(-?[0-9]?[^0-9_\- ,][^0-9_,]+)(?:_[0-9]+)?\b" -AllMatches -List | % { $_.Matches } | % { $_.Groups[1].Value } | Add-Tag
    }

    if ($ReplaceTags) {
        foreach ($ReplaceTag in ($ReplaceTags | % { $_.Split(",") })) {
            $TagParts = $ReplaceTag.Split(":")
            $OldTag = $TagParts[0]?.Trim()
            $NewTag = $TagParts[1]?.Trim()
    
            if ($OldTag -and $NewTag -and $FileTagsSet.Contains($OldTag)) {
                $OldTag | Remove-Tag
                $NewTag | Add-Tag
            }
        }
    }

    $RemoveTags | Remove-Tag

    if ($RemoveRedundantTags) {
        $FileTags.ToArray() | Select-String -Pattern '^([^ ]+) ([^ ]+)$' | % { $_.Matches.Groups[2].Value } | Where-Object { !$TagsToKeep.Contains($_) } | Remove-Tag
        $FileTags.ToArray() | Select-String -Pattern '^([^ ]+) ([^ ]+)$' | % { $_.Matches.Groups[2].Value } | Where-Object { !$TagsToKeep.Contains($_) } | % { $RedundantTags[$_] } | Remove-Tag
        $FileTags.ToArray() | % { $RedundantTags[$_] } | Remove-Tag
    }

    if ($RemoveUnwantedTags) {
        $UnwantedTags | Remove-Tag
    }

    $FileTagsSet | % { $CountByTags[$_] = ($CountByTags[$_] ?? 0) + 1 }

    $TagFiles.Add(@{
            File            = $File
            OriginalContent = $FileContent
            Directory       = $File.Directory
            Tags            = $FileTags
            TagsAdded       = $TagsAdded
            TagsRemoved     = $TagsRemoved
        }) | Out-Null

}

if ($OrganizeFilesBy) {
    Move-By-Category -CategoryName $OrganizeFilesBy
}

if ($SuffixFileCount) {
    $FilesByDirectory = $TagFiles | Group-Object -Property "Directory"

    foreach ($Group in $FilesByDirectory) {
        $DirFullName = $Group.Name
        $Dir = Get-Item -LiteralPath $DirFullName
        if ($Dir.FullName -eq $PathDirectory.FullName -or $Dir.Name.StartsWith("_")) {
            continue
        }

        $DirFiles = $Group.Group
        $ParentDirFullName = $Dir.Parent.FullName
        $NewDirName = $Dir.Name | Select-String -Pattern "([^0-9]*[^0-9_]+)(?:_[0-9]+)?" | % { $_.Matches.Groups[1].Value }
        if ($NewDirName) {
            $NewDirName = $NewDirName.Trim() + "_" + $DirFiles.Count
        }

        if ($NewDirName -and $NewDirName -ne $Dir.Name) {
            if (!$DryRun) {
                $NewDirectory = Rename-Item -LiteralPath $DirFullName -NewName "$ParentDirFullName\$NewDirName" -PassThru

                foreach ($TagFile in $DirFiles) {
                    $TagFile.File = Get-Item -LiteralPath "$ParentDirFullName\$NewDirName\$($TagFile.File.Name)"
                    $TagFile.Directory = $NewDirectory
                }
            }
        }
    }
}

foreach ($TagFile in $TagFiles) {
    if ($SortTagsByCount) {
        $TagIndex = 1
        $TagFile.Tags = $TagFile.Tags | `
            % { @{ Tag = $_; CountNeg = - $CountByTags[$_]; KeepIndex = ($TagIndex -le $KeepTags) ? $TagIndex : $TagFile.Tags.Count; Index = $TagIndex++ } } | `
            Sort-Object -Property "KeepIndex", "CountNeg", "Tag" | % { $_.Tag }
    }

    if (!$DryRun) {
        $FileTagsString = ($TagFile.Tags -join ", ")
        if ($TagFile.OriginalContent -ne $FileTagsString) {
            Set-Content -NoNewLine -LiteralPath $TagFile.File.FullName -Value $FileTagsString
        }
    }
}

$MaxFileNameLength = $TagFiles | % { ($LogFolderName ? $_.File.Name : (Resolve-Path -LiteralPath $_.File.FullName -Relative -RelativeBasePath $Path)).Length } | Sort-Object -Descending | Select-Object -First 1
$MaxFolderLength = ($TagFiles | % { (Resolve-Path -LiteralPath $_.Directory.FullName -Relative -RelativeBasePath $Path).Length } | Measure-Object -Maximum).Maximum

$FileNumber = 1
foreach ($TagFile in $TagFiles) {
    Write-Host "$($FileNumber.ToString().PadLeft($FileCountString.Length, '0'))/$FileCountString" -NoNewline

    if ($LogFolderName) {
        Write-Host " | $((Resolve-Path -LiteralPath $TagFile.Directory.FullName -Relative -RelativeBasePath $Path).PadLeft($MaxFolderLength, ' '))" -NoNewline -ForegroundColor Blue
    }

    if ($LogFileName) {
        Write-Host " | $(($LogFolderName ? $TagFile.File.Name : (Resolve-Path -LiteralPath $TagFile.File.FullName -Relative -RelativeBasePath $Path)).PadRight($MaxFileNameLength, ' '))" -NoNewline -ForegroundColor Blue
    }

    if ($LogTags) {
        Write-Host " | " -NoNewline

        $TagIndex = 0
        foreach ($Tag in $TagFile.Tags) {
            if ($TagIndex -gt 0) {
                Write-Host ", " -NoNewline
            }

            if ($FindTagsSet.Contains($Tag)) {
                Write-Host $Tag -NoNewline -ForegroundColor DarkYellow
            }
            elseif ($TagFile.TagsAdded.Contains($Tag)) {
                Write-Host $Tag -NoNewline -ForegroundColor Green
            }
            else {
                Write-Host $Tag -NoNewline
            }
            $TagIndex += 1
        }

        foreach ($Tag in $TagFile.TagsRemoved) {
            if ($TagIndex -gt 0) {
                Write-Host ", " -NoNewline
            }

            Write-Host $Tag -NoNewline -ForegroundColor Red
            $TagIndex += 1
        }
    }

    Write-Host "" # New line
    $FileNumber += 1
}

if ($LogStats) {
    $AllTags = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $AllTags.UnionWith([string[]]@($TagFiles | % { $_.Tags }))

    $TagsAdded = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsAdded.UnionWith([string[]]@($TagFiles | % { $_.TagsAdded }))

    Write-Host "--  Tag statistics:  ".PadRight(80, "-")

    $TagsByCount = [System.Collections.Generic.Dictionary[int, String[]]]::new()
    $CountByTags.Keys | % { $TagsByCount[$CountByTags[$_]] = $TagsByCount[$CountByTags[$_]] + @($_) }
    foreach ($TagKey in $TagsByCount.Keys | Sort-Object -Descending) {
        Write-Host "$($TagKey.ToString().PadLeft($FileCountString.Length, " ")): " -NoNewline

        $TagIndex = 0
        foreach ($Tag in $TagsByCount[$TagKey]) {
            if ($TagIndex -gt 0) {
                Write-Host ", " -NoNewline
            }

            if ($FindTagsSet.Contains($Tag)) {
                Write-Host $Tag -NoNewline -ForegroundColor DarkYellow
            }
            elseif ($TagsAdded.Contains($Tag)) {
                Write-Host $Tag -NoNewline -ForegroundColor Green
            }
            else {
                Write-Host $Tag -NoNewline
            }
            $TagIndex += 1
        }

        Write-Host "" # New line
    }

    foreach ($Key in $TagsByCategory.Keys) {
        Write-Tag-Category-Stats -CategoryName $Key -Silent:($TagsByCategory.ContainsKey($OrganizeFilesBy) -and $Key -ne $OrganizeFilesBy)
    }

    Write-Host "--  Tag scores:  ".PadRight(80, "-")
    $ItemIndex = 0
    foreach ($Item in $CategoryScores) {
        if ($ItemIndex -gt 0) {
            Write-Host ", " -NoNewline
        }
        Write-Host "$($Item.Category): " -NoNewline
        Write-Host ("{0:n2}" -f $Item.Score) -ForegroundColor ($Item.Score -ge $TagScoreThreshold ? "Green" : "Red") -NoNewline
        $ItemIndex++
    }
    Write-Host "`nTotal: " -NoNewline
    $FinalScore = ($CategoryScores | % { $_.Score } | Measure-Object -Average).Average
    Write-Host ("{0:n2}" -f $FinalScore) -ForegroundColor ($FinalScore -ge $TagScoreThreshold ? "Green" : "Red")

    $FileTagsKept = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $FileTagsKept.UnionWith([string[]]@($TagFiles | % { $_.Tags | Select-Object -First $KeepTags }))

    # Suggest removing tags present for > 80% of the files (unless included in $TagsToKeep or $FileTagsKept)
    $TagsTooFrequent = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsTooFrequent.UnionWith([string[]]@(`
                $TagsByCount.Keys | `
                Where-Object { $_ -gt ($TagFiles.Count * 0.8) } | `
                % { $TagsByCount[$_] } | `
                Where-Object { $Tag = $_; !$TagsAdded.Contains($Tag) -and !$FileTagsKept.Contains($Tag) -and !($TagsToKeep | Where-Object { $Tag -match "\b$([Regex]::Escape($_))\b" }) }
        ))

    # Suggest removing tags if above warning threshold
    $TagsAboveThreshold = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsAboveThreshold.UnionWith([string[]]@(`
                $CountByTags.Keys | `
                Where-Object { $CountByTags[$_] -gt ($TagFiles.Count * ($TagsToWarn[$_] ?? [System.Int32]::MaxValue)) } | `
                Where-Object { $Tag = $_; !$TagsAdded.Contains($Tag) -and !$FileTagsKept.Contains($Tag) }
        ))

    # Suggest removing tags not part of known booru tag list (unless included in $FileTagsKept)
    $TagsUnknown = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsUnknown.UnionWith([string[]]@(`
                $CountByTags.Keys | `
                Where-Object { $Tag = $_; !$TagsAdded.Contains($Tag) -and !$FileTagsKept.Contains($Tag) -and !$KnownBooruTags.ContainsKey($Tag) }
        ))

    # Suggest removing tags with less than 1k booru images
    $TagsBelow1k = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsBelow1k.UnionWith([string[]]@(`
                $CountByTags.Keys | `
                Where-Object { $Tag = $_; !$TagsAdded.Contains($Tag) -and !$FileTagsKept.Contains($Tag) -and $KnownBooruTags.ContainsKey($Tag) -and $KnownBooruTags[$Tag] -lt 1000 }
        ))

    # Suggest removing tags that are too broad (unless included in $FileTagsKept)
    $TagsTooBroad = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsTooBroad.UnionWith([string[]]@(`
                $CountByTags.Keys | `
                Where-Object { $Tag = $_; !$TagsAdded.Contains($Tag) -and !$FileTagsKept.Contains($Tag) -and $TagsWithoutColor.Contains($Tag) }
        ))
    
    # Suggest removing tags part of unwanted tag list
    $TagsInUnwantedList = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::InvariantCultureIgnoreCase)
    $TagsInUnwantedList.UnionWith([string[]]@($UnwantedTags | Where-Object { $AllTags.Contains($_) }))

    if ($TagsInUnwantedList.Count -gt 0 -or $TagsUnknown.Count -gt 0 -or $TagsTooFrequent.Count -gt 0 -or $TagsAboveThreshold.Count -gt 0 -or $TagsTooBroad.Count -gt 0 -or $TagsBelow1k.Count -gt 0) {
        Write-Host "".PadRight(80, "-")

        if ($TagsInUnwantedList.Count -gt 0) {
            Write-Host "Suggested to untag (part of unwanted list): " -NoNewline
            Write-Host ($TagsInUnwantedList -Join ", ") -ForegroundColor Red
        }

        if ($TagsUnknown.Count -gt 0) {
            Write-Host "Suggested to untag (unknown or has < 500 booru count): " -NoNewline
            Write-Host ($TagsUnknown -Join ", ") -ForegroundColor Red
        }

        if ($TagsBelow1k.Count -gt 0) {
            Write-Host "Suggested to untag (has < 1k booru count): " -NoNewline
            Write-Host ($TagsBelow1k -Join ", ") -ForegroundColor Red
        }

        if ($TagsTooFrequent.Count -gt 0) {
            Write-Host "Suggested to untag (present in > 80% of files): " -NoNewline
            Write-Host ($TagsTooFrequent -Join ", ") -ForegroundColor Red
        }

        if ($TagsAboveThreshold.Count -gt 0) {
            Write-Host "Suggested to untag or delete (above recommended threshold): " -NoNewline
            Write-Host ($TagsAboveThreshold -Join ", ") -ForegroundColor Red
        }

        if ($TagsTooBroad.Count -gt 0) {
            Write-Host "Suggested to change (too broad): " -NoNewline
            Write-Host ($TagsTooBroad -Join ", ") -ForegroundColor Red
        }

        if (!$RemoveUnwantedTags) {
            Write-Host "Tip: add -RemoveUnwantedTags parameter to remove all unwanted tags"
        }
    }
}
