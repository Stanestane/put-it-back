$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceArchive = 'D:/Godot/ExportTemplates/4.7.2.stable/android_source.zip'
$buildRoot = Join-Path $projectRoot 'android/build'
if (-not (Test-Path -LiteralPath "$buildRoot/gradlew.bat")) {
    New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $buildRoot -Force
    Set-Content -LiteralPath "$projectRoot/android/.build_version" -Value '4.7.2.stable' -NoNewline
}
# Godot's Windows console wrapper waits for child processes; a persistent
# Gradle daemon keeps an otherwise successful command-line export open.
$propertiesPath = Join-Path $buildRoot 'gradle.properties'
if (-not (Select-String -LiteralPath $propertiesPath -Pattern '^org.gradle.daemon=false$' -Quiet)) {
    Add-Content -LiteralPath $propertiesPath -Value "`norg.gradle.daemon=false"
}
$env:JAVA_HOME = 'D:/Godot/Android/Jdk/temurin-17'
if (-not (Test-Path -LiteralPath 'D:/Godot/Android/Sdk/platforms/android-36/android.jar') -or -not (Test-Path -LiteralPath 'D:/Godot/Android/Sdk/build-tools/36.1.0/aapt.exe')) {
    & 'D:/Godot/Android/Sdk/cmdline-tools/latest/bin/android.exe' '--sdk=D:/Godot/Android/Sdk' sdk install 'platforms/android-36' 'build-tools/36.1.0'
    if ($LASTEXITCODE -ne 0) { Write-Warning "Android CLI returned $LASTEXITCODE; checking installed packages below." }
}
if (-not (Test-Path -LiteralPath 'D:/Godot/Android/Sdk/platforms/android-36/android.jar')) { throw 'Android 36 platform missing' }
if (-not (Test-Path -LiteralPath 'D:/Godot/Android/Sdk/build-tools/36.1.0/aapt.exe')) { throw 'Build tools 36.1 missing' }
