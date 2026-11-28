# Compila la app de Android de TREVIX en Windows: APK (instalación directa) y AAB (Google Play), firmados con la clave
# de TREVIX. Requisitos: Flutter estable, Android Studio (su JDK) y el SDK de Android con cmdline-tools.
#
#   $env:TREVIX_KEYSTORE = 'C:\ruta\trevix-release.jks'
#   $env:TREVIX_KEYSTORE_PASSWORD = '...'
#   .\mobile\android_overrides\build-android.ps1 -BuildNumber 125
#   .\mobile\android_overrides\build-android.ps1   # usa version/build de pubspec.yaml
#
# Gradle y el NDK fallan con espacios en la ruta, así que el proyecto se copia a -WorkDir antes de compilar.
param(
    [int]$BuildNumber = 0,
    [string]$WorkDir = "$env:USERPROFILE\dev\trevix-mobile",
    [string]$OutDir = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'APPS TREVIX'),
    [string]$Flutter = "$env:USERPROFILE\dev\flutter\bin"
)
$ErrorActionPreference = 'Stop'

$pubspec = Join-Path (Split-Path -Parent $PSScriptRoot) 'pubspec.yaml'
if (-not (Test-Path $pubspec)) { throw "No se encontró pubspec.yaml en $pubspec" }
$versionLine = (Select-String -Path $pubspec -Pattern '^\s*version:\s*' | Select-Object -First 1).Line
if (-not $versionLine) { throw 'pubspec.yaml no define version' }
if ($versionLine -match 'version:\s*([0-9]+(?:\.[0-9]+)*)\+(\d+)') {
    $appVersion = $Matches[1]
    $pubBuild = [int]$Matches[2]
} elseif ($versionLine -match 'version:\s*([0-9]+(?:\.[0-9]+)*)') {
    $appVersion = $Matches[1]
    $pubBuild = 1
} else {
    throw "version en pubspec no reconocida: $versionLine"
}
if ($BuildNumber -le 0) { $BuildNumber = $pubBuild }

if (-not $env:TREVIX_KEYSTORE -or -not (Test-Path $env:TREVIX_KEYSTORE) -or -not $env:TREVIX_KEYSTORE_PASSWORD) {
    throw 'Define TREVIX_KEYSTORE (ruta del .jks) y TREVIX_KEYSTORE_PASSWORD antes de compilar.'
}
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
# Evitar GRADLE_USER_HOME del sandbox de Cursor (sin distros) y usar la caché real del usuario.
if (-not $env:GRADLE_USER_HOME -or $env:GRADLE_USER_HOME -like '*cursor-sandbox-cache*') {
    $env:GRADLE_USER_HOME = Join-Path $env:USERPROFILE '.gradle'
}
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

# configure_gradle.py solo corre al generar la carpeta: si es de antes de Firebase se genera de nuevo.
if ((Test-Path android) -and -not (Select-String -Path android\app\build.gradle.kts -Pattern 'firebase-messaging' -SimpleMatch -Quiet)) {
    Remove-Item -Recurse -Force android
}
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
Step 'Iconos alternativos' { python tool\prepare_alternate_icons.py --android android }
Step 'Revisar el código' {
  # Solo errores fatales; Flutter escribe el resumen en stderr y puede devolver 1 con avisos info.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $analyze = (& flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Out-String)
  $ErrorActionPreference = $prev
  if ($analyze -match '(?m)^\s*error\s*-') { throw "flutter analyze encontró errores." }
}
Step 'APK' { flutter build apk --release --build-number=$BuildNumber }
Step 'AAB' { flutter build appbundle --release --build-number=$BuildNumber }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$apkName = "APK $appVersion.apk"
$aabName = "ABB $appVersion.aab"
Copy-Item build\app\outputs\flutter-apk\app-release.apk (Join-Path $OutDir $apkName) -Force
Copy-Item build\app\outputs\bundle\release\app-release.aab (Join-Path $OutDir $aabName) -Force
Write-Host "Listo: $apkName y $aabName (build $BuildNumber) en $OutDir"
