$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "android_env.ps1")

$keystorePath = Join-Path $root "android\app\upload-keystore.jks"
$propertiesPath = Join-Path $root "android\key.properties"

if (Test-Path $keystorePath) {
    Remove-Item -LiteralPath $keystorePath -Force
}

$chars = 48..57 + 65..90 + 97..122
$password = -join ($chars | Get-Random -Count 32 | ForEach-Object { [char]$_ })

keytool `
    -genkeypair `
    -v `
    -keystore $keystorePath `
    -storetype JKS `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -alias upload `
    -storepass $password `
    -keypass $password `
    -dname "CN=Kuchi Toji Watch, OU=Release, O=Kuchi Toji Watch, L=Tokyo, ST=Tokyo, C=JP"

[System.IO.File]::WriteAllLines(
    $propertiesPath,
    @(
        "storePassword=$password",
        "keyPassword=$password",
        "keyAlias=upload",
        "storeFile=upload-keystore.jks"
    ),
    [System.Text.Encoding]::ASCII
)

$lines = [System.IO.File]::ReadAllLines($propertiesPath, [System.Text.Encoding]::ASCII)
Write-Host "Generated upload key and key.properties with $($lines.Length) entries."
