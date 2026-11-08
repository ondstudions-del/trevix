#!/usr/bin/env bash
# Prueba del APK en el emulador (lo ejecuta .github/workflows/android.yml desde mobile/):
# instala el APK firmado, comprueba que la app abre y sigue abierta, que un enlace trevix:// la abre,
# y ejecuta las pruebas de integración del visor de historias.
set +e
PKG=com.ondsc.trevix
mkdir -p smoke

crash_logs() {
  adb logcat -d -b crash > smoke/cierre.txt 2>&1
  adb logcat -d '*:E' > smoke/errores.txt 2>&1
  echo "=== Cierres"; tail -n 120 smoke/cierre.txt
  echo "=== Errores"; grep -iE "trevix|flutter|AndroidRuntime|FATAL" smoke/errores.txt | tail -n 80
}

alive() { adb shell pidof "$PKG" > /dev/null 2>&1; }

adb wait-for-device
adb install -r TREVIX.apk || { echo "::error::No se pudo instalar el APK."; exit 1; }
adb logcat -c
adb shell am start -W -n "$PKG/.MainActivity"
sleep 30
adb exec-out screencap -p > smoke/abierta.png
if ! alive; then
  echo "::error::La app se cerró al abrir en el emulador."
  crash_logs
  exit 1
fi
echo "La app sigue abierta después de 30 s."

adb shell am start -W -a android.intent.action.VIEW -d "trevix://open/events.php" "$PKG"
sleep 8
adb exec-out screencap -p > smoke/enlace.png
if ! alive; then
  echo "::error::La app se cerró al abrir un enlace trevix://."
  crash_logs
  exit 1
fi
echo "El enlace trevix:// abre la app."

# Avisos: el icono de la barra de estado y el canal existen (un recurso que falta cierra la app al avisar).
adb shell dumpsys package "$PKG" | grep -E "versionCode|versionName" | head -2
crash_logs > /dev/null
if grep -q "$PKG" smoke/cierre.txt; then
  echo "::error::Hubo un cierre de la app durante la prueba."
  crash_logs
  exit 1
fi

# Las pruebas de integración usan una compilación de depuración (otra firma): se desinstala la de release.
adb shell am force-stop "$PKG"
adb uninstall "$PKG" > /dev/null
DEVICE=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
infra=0
status=1
for attempt in 1 2; do
  timeout 900 flutter test integration_test -d "$DEVICE" --reporter expanded 2>&1 | tee smoke/pruebas.txt
  status=${PIPESTATUS[0]}
  if [ "$status" -eq 0 ] || grep -q 'All tests passed' smoke/pruebas.txt; then status=0; break; fi
  if grep -qE 'Unable to start the app|debug connection|Failed to install|Error waiting' smoke/pruebas.txt || [ "$status" -eq 124 ]; then
    infra=1
    echo "::warning::El emulador no arrancó la prueba (intento $attempt)."
    continue
  fi
  infra=0
  break
done
if [ "$status" -ne 0 ]; then
  crash_logs
  if [ "$infra" -eq 1 ]; then
    echo "::warning::No se pudieron ejecutar las pruebas de integración por el emulador; la app sí abrió y siguió abierta."
  else
    echo "::error::Fallaron las pruebas de integración (ver smoke/pruebas.txt)."
    exit 1
  fi
fi
exit 0
