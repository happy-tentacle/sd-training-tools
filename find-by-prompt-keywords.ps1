param (
    [Parameter(Mandatory = $true)] [string] $Path,
    [Parameter(Mandatory = $true)] [string[]] $Keywords
)

$ErrorActionPreference = "Stop"

foreach ($File in Get-ChildItem -Path $Path -File -Recurse) {
    $Prompt = $File | Get-Content -Encoding ascii -TotalCount 40 | Join-String

    $Match = $True
    foreach ($Keyword in $Keywords) {
        if (!$Prompt.Contains($Keyword)) {
            $Match = $false
            break
        }
    }

    if ($Match) {
        $File.FullName
    }
}
