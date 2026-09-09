$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath('D:/Put It Back')
$destinationRoot = [IO.Path]::GetFullPath('E:/Godot Projects/Put It Back')
if ($sourceRoot -ne 'D:\Put It Back' -or $destinationRoot -ne 'E:\Godot Projects\Put It Back') { throw 'Unexpected move paths' }
Copy-Item -LiteralPath "$sourceRoot/project.godot" -Destination "$destinationRoot/project.godot" -Force
Copy-Item -LiteralPath "$sourceRoot/assets/icon.svg" -Destination "$destinationRoot/assets/icon.svg" -Force
Copy-Item -LiteralPath "$sourceRoot/scripts/extra_levels.gd" -Destination "$destinationRoot/scripts/extra_levels.gd" -Force
Copy-Item -LiteralPath "$sourceRoot/tools/build.ps1" -Destination "$destinationRoot/tools/build.ps1" -Force
Copy-Item -LiteralPath "$sourceRoot/tools/finish-move.ps1" -Destination "$destinationRoot/tools/finish-move.ps1" -Force
& "$destinationRoot/tools/build.ps1"
foreach ($file in (Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force)) {
    $relative = [IO.Path]::GetRelativePath($sourceRoot,$file.FullName)
    if ($relative.StartsWith('.godot\') -or $relative.StartsWith('verification\') -or $relative.EndsWith('.import')) { continue }
    $copied = Join-Path $destinationRoot $relative
    if (-not (Test-Path -LiteralPath $copied)) { throw "Missing copied source: $relative" }
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $copied).Hash) { throw "Source mismatch: $relative" }
}
if ((git -C $sourceRoot rev-parse HEAD) -ne (git -C $destinationRoot rev-parse HEAD)) { throw 'Git history mismatch' }
if ((git -C $sourceRoot remote get-url origin) -ne (git -C $destinationRoot remote get-url origin)) { throw 'Git remote mismatch' }
Set-Location -LiteralPath 'D:/'
Remove-Item -LiteralPath $sourceRoot -Recurse -Force
Write-Output "Move completed: $destinationRoot"
