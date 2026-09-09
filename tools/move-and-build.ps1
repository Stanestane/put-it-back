$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath('D:/Put It Back')
$destinationRoot = [IO.Path]::GetFullPath('E:/Godot Projects/Put It Back')
if ($sourceRoot -ne 'D:\Put It Back' -or $destinationRoot -ne 'E:\Godot Projects\Put It Back') { throw 'Unexpected move paths' }
if (-not (Test-Path -LiteralPath "$sourceRoot/.git")) { throw 'Source repository missing' }
if (Test-Path -LiteralPath $destinationRoot) { throw 'Destination already exists; refusing to overwrite it' }
$originalHead = git -C $sourceRoot rev-parse HEAD
$originalRemote = git -C $sourceRoot remote get-url origin
Copy-Item -LiteralPath $sourceRoot -Destination $destinationRoot -Recurse -Force
$files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($sourceRoot, $file.FullName)
    $copied = Join-Path $destinationRoot $relative
    if (-not (Test-Path -LiteralPath $copied)) { throw "Missing copied file: $relative" }
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $copied).Hash) { throw "File mismatch: $relative" }
}
if ((git -C $destinationRoot rev-parse HEAD) -ne $originalHead) { throw 'Git history mismatch' }
if ((git -C $destinationRoot remote get-url origin) -ne $originalRemote) { throw 'Git remote mismatch' }
Write-Output "Verified $($files.Count) copied files; Git HEAD and origin unchanged."
& "$destinationRoot/tools/build.ps1"
if (-not (Test-Path -LiteralPath "$destinationRoot/exports/android/PutItBack.apk")) { throw 'APK missing' }
Set-Location -LiteralPath 'D:/'
# The exact source and destination were validated above, every copied file was
# hash-checked, and both exports completed before removing the original tree.
Remove-Item -LiteralPath $sourceRoot -Recurse -Force
Write-Output "Move completed: $destinationRoot"
