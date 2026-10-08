$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$godotEngine = 'D:/Godot/Engine/Godot_v4.7.2-stable_win64_console.exe'
Set-Location -LiteralPath $projectRoot
if (-not (Test-Path -LiteralPath 'resources/telemetry_config.json')) {
    throw 'Run tools/configure-telemetry.ps1 before building telemetry QA.'
}
& "$PSScriptRoot/setup-android.ps1"
New-Item -ItemType Directory -Force exports/android,verification | Out-Null
$presetPath = Join-Path $projectRoot 'export_presets.cfg'
$originalBytes = [IO.File]::ReadAllBytes($presetPath)
$original = [Text.Encoding]::UTF8.GetString($originalBytes)
if ($original.Contains('[preset.2]')) { throw 'Preset 2 already exists; review the QA preset allocation.' }
$androidStart = $original.IndexOf('[preset.1]')
if ($androidStart -lt 0) { throw 'Android preset 1 is missing.' }
$qa = $original.Substring($androidStart).Replace('[preset.1', '[preset.2')
$qa = $qa.Replace('name="Android"', 'name="Android Telemetry QA"')
$qa = $qa.Replace('exports/android/PutItBack.apk', 'exports/android/PutItBack-QA.apk')
$qa = $qa.Replace('package/unique_name="com.vdsystem.putitback"', 'package/unique_name="com.vdsystem.putitback.qa"')
$qa = $qa.Replace('package/name="Put It Back"', 'package/name="Put It Back QA"')
if ($qa.Contains('command_line/extra_args=')) { throw 'Review existing Android launch arguments before adding QA flags.' }
$qa += "`ncommand_line/extra_args=`"-- --telemetry-test`"`n"
try {
    [IO.File]::WriteAllText($presetPath, $original + "`n" + $qa, [Text.UTF8Encoding]::new($false))
    $result = & $godotEngine --headless --path . --export-debug 'Android Telemetry QA' 2>&1
    $code = $LASTEXITCODE
    $result | Set-Content -LiteralPath verification/android-telemetry-qa-export.log
    if ($code -ne 0 -or ($result | Select-String 'SCRIPT ERROR:|ERROR:')) {
        $result | Write-Output
        throw 'QA export failed; see verification/android-telemetry-qa-export.log.'
    }
} finally {
    [IO.File]::WriteAllBytes($presetPath, $originalBytes)
}
& 'D:/Godot/Android/Sdk/build-tools/35.0.1/apksigner.bat' verify --verbose exports/android/PutItBack-QA.apk | Set-Content verification/android-telemetry-qa-signature.log
if ($LASTEXITCODE -ne 0) { throw 'QA APK signature verification failed.' }
Write-Output 'Built exports/android/PutItBack-QA.apk (separate package; test telemetry only; opt-in still required).'
