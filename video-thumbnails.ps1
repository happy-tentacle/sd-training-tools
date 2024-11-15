param (
    [Parameter(Mandatory = $true)] [string] $Directory,
    [Parameter(Mandatory = $false)] [Switch] $Overwrite
)

$columns = 6
$rows = 60
$width = 1920
$quality = 100
$backcolor = "000000"
$gap = 0
$edge = 0
$process_start_time = Get-Date

function Pause($Message = "Press any key to continue...") {
    Write-Host -NoNewLine $Message
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Get-ElapsedTime {
    param($start_time)

    $runtime = $(Get-Date) - $start_time
    $retStr = [string]::format("{0} days, {1} hours, {2} minutes, {3}.{4} seconds", `
            $runtime.Days, `
            $runtime.Hours, `
            $runtime.Minutes, `
            $runtime.Seconds, `
            $runtime.Milliseconds)
    $retStr
}

$Items = Get-ChildItem -LiteralPath $Directory -File -Recurse -Exclude "*.jpg", "*.png" | Select-Object -ExpandProperty FullName
foreach ($item in $items) {
    $filePathNoExt = [System.IO.Path]::GetDirectoryName($item) + "\" + [System.IO.Path]::GetFileNameWithoutExtension($item)
    if ($Overwrite -or !(Test-Path -LiteralPath "$($filePathNoExt).jpg" -PathType Leaf)) {
        Write-Host "`nFile: $item"
        # C:\tools\mtn\mtn.exe -P -h 0 -o .jpg -c $columns -r $rows -w $width -g $gap -j $quality -D $edge -L 4:2 -k $backcolor -f arialbd.ttf -F FFFFFF:12:arialbd.ttf:FFFFFF:000000:10 "$item"
		C:\tools\mtn\mtn.exe -P -h 0 -o .jpg -s 10 -z -c $columns -w $width -g $gap -j $quality -D $edge -L 4:2 -k $backcolor -f arialbd.ttf -F FFFFFF:12:arialbd.ttf:FFFFFF:000000:10 "$item"
    }
}

$elapsed_time = Get-ElapsedTime($process_start_time)
Write-Host "`nTime elapsed: " $elapsed_time "`n"

Pause