$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$env:JAVA_HOME = Join-Path $Root ".tools\jdk-17.0.19+10"
$env:ANDROID_HOME = Join-Path $Root ".tools\android-sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\platform-tools;C:\Program Files\Git\cmd;$Root\.tools\flutter\bin;$env:PATH"

Write-Host "Android/Flutter environment configured for this shell."
