# Compila la app de Android de TREVIX en Windows: APK (instalación directa) y AAB (Google Play), firmados con la clave
# de TREVIX. Requisitos: Flutter estable, Android Studio (su JDK) y el SDK de Android con cmdline-tools.
#
#   $env:TREVIX_KEYSTORE = 'C:\ruta\trevix-release.jks'
#   $env:TREVIX_KEYSTORE_PASSWORD = '...'
#   .\mobile\android_overrides\build-android.ps1 -BuildNumber 6
#
# Gradle y el NDK fallan con espacios en la ruta, así que el proyecto se copia a -WorkDir antes de compilar.
param(
    [Parameter(Mandatory = $true)][int]$BuildNumber,
    [string]$WorkDir = "$env:USERPROFILE\dev\trevix-mobile",
    [string]$OutDir = [Environment]::GetFolderPath('Desktop'),
    [string]$Flutter = "$env:USERPROFILE\dev\flutter\bin"
)
$ErrorActionPreference = 'Stop'

if (-not $env:TREVIX_KEYSTORE -or -not (Test-Path $env:TREVIX_KEYSTORE) -or -not $env:TREVIX_KEYSTORE_PASSWORD) {
    throw 'Define TREVIX_KEYSTORE (ruta del .jks) y TREVIX_KEYSTORE_PASSWORD antes de compilar.'
}
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
$env:Path = "$Flutter;$env:JAVA_HOME\bin;$env:Path"

function Step([string]$name, [scriptblock]$run) {
    Write-Host "==> $name"
    & $run
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Falló: $name (código $LASTEXITCODE)" }
}

$src = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force $WorkDir | Out-Null
# Rutas completas: un nombre suelto («android») excluiría también las carpetas de los plugins locales (packages/).
$skip = foreach ($d in 'build', '.dart_tool', 'android', 'ios') { Join-Path $src $d; Join-Path $WorkDir $d }
Step 'Copiar el proyecto' { robocopy $src $WorkDir /MIR /XD @skip /NFL /NDL /NJH /NJS /NP | Out-Null; $global:LASTEXITCODE = 0 }
Set-Location $WorkDir

if (-not (Test-Path android)) {
    Step 'Generar la carpeta de Android' { flutter create --platforms=android --org com.ondsc --project-name trevix . }
    if (Test-Path test) { Remove-Item -Recurse -Force test }
    Copy-Item -Recurse -Force android_overrides\app\* android\app\
    Step 'Ajustar Gradle' { python android_overrides\configure_gradle.py | Out-Null }
} else {
    Copy-Item -Recurse -Force android_overrides\app\* android\app\
}

Step 'Dependencias' { flutter pub get }
Step 'Icono' { dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml }
Step 'Revisar el código' { flutter analyze --no-fatal-infos --no-fatal-warnings }
Step 'APK' { flutter build apk --release --build-number=$BuildNumber }
Step 'AAB' { flutter build appbundle --release --build-number=$BuildNumber }

Copy-Item build\app\outputs\flutter-apk\app-release.apk (Join-Path $OutDir 'TREVIX.apk') -Force
Copy-Item build\app\outputs\bundle\release\app-release.aab (Join-Path $OutDir 'TREVIX.aab') -Force
Write-Host "Listo: TREVIX.apk y TREVIX.aab (compilación $BuildNumber) en $OutDir"
