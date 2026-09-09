$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$godotEngine = 'D:/Godot/Engine/Godot_v4.7.2-stable_win64_console.exe'
Set-Location -LiteralPath $projectRoot
& "$PSScriptRoot/setup-android.ps1"
New-Item -ItemType Directory -Force exports/windows,exports/android,verification | Out-Null
Set-Content -LiteralPath verification/.gdignore -Value ''
Set-Content -LiteralPath exports/.gdignore -Value ''
function Invoke-GodotChecked([string[]]$Arguments, [string]$Log) {
    $result = & $godotEngine @Arguments 2>&1
    $code = $LASTEXITCODE
    $result | Set-Content -LiteralPath $Log
    if ($code -ne 0 -or ($result | Select-String 'SCRIPT ERROR:|ERROR:')) {
        $result | Write-Output
        throw "Godot failed: $Log"
    }
    Write-Output "Passed: $Log"
}
Invoke-GodotChecked @('--headless','--path','.','--editor','--import','--quit') 'verification/import.log'
Invoke-GodotChecked @('--headless','--path','.','--script','tools/check_ads.gd') 'verification/ads-parser.log'
Invoke-GodotChecked @('--headless','--path','.','--quit-after','300','--','--self-test') 'verification/tests.log'
if (-not (Select-String -Path verification/tests.log -Pattern 'SELF TEST PASSED')) { throw 'Test success marker missing' }
Invoke-GodotChecked @('--path','.','--rendering-method','gl_compatibility','--audio-driver','Dummy','--','--gallery') 'verification/gallery.log'
Invoke-GodotChecked @('--headless','--path','.','--export-release','Windows Desktop') 'verification/windows-export.log'
Invoke-GodotChecked @('--headless','--path','.','--export-debug','Android') 'verification/android-export.log'
& "$projectRoot/exports/windows/PutItBack.exe" --headless --quit-after 3 --log-file "$projectRoot/verification/windows-smoke.log"
if ($LASTEXITCODE -ne 0) { throw 'Windows executable smoke test failed' }
$env:JAVA_HOME = 'D:/Godot/Android/Jdk/temurin-17'
& 'D:/Godot/Android/Sdk/build-tools/35.0.1/apksigner.bat' verify --verbose exports/android/PutItBack.apk | Set-Content verification/apk-signature.log
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
& 'D:/Godot/Android/Sdk/build-tools/35.0.1/aapt.exe' dump badging exports/android/PutItBack.apk | Set-Content verification/apk-manifest.log
if ($LASTEXITCODE -ne 0) { throw 'APK manifest verification failed' }
Get-FileHash exports/windows/PutItBack.exe,exports/android/PutItBack.apk | Format-Table -AutoSize | Out-String | Set-Content exports/SHA256.txt
Get-Item exports/windows/PutItBack.exe,exports/android/PutItBack.apk | Select-Object FullName,Length
