"""Ajusta android/app/build.gradle(.kts) que genera «flutter create» (lo ejecuta .github/workflows/android.yml):

- minSdk 23 como mínimo (notas de voz, almacenamiento seguro);
- desugaring de Java 8+ (lo exige flutter_local_notifications);
- firma de release con la clave de TREVIX (variables TREVIX_KEYSTORE y TREVIX_KEYSTORE_PASSWORD), para que cada
  APK nuevo se instale encima del anterior sin perder la sesión.

Falla con un mensaje claro si la plantilla cambió y no encuentra lo que debe ajustar.
"""
import pathlib
import re
import sys

app = pathlib.Path("android/app")
kts = app / "build.gradle.kts"
if not kts.exists():
    sys.exit("No se encontró android/app/build.gradle.kts (¿cambió la plantilla de Flutter?).")
src = kts.read_text(encoding="utf-8")


def sub(pattern: str, repl: str, text: str, what: str, flags: int = 0) -> str:
    new, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        sys.exit(f"build.gradle.kts: no se pudo ajustar {what}.")
    return new


src = sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)", src, "minSdk")
src = sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", src, "compileOptions")

signing = '''signingConfigs {
        create("release") {
            val keystore = System.getenv("TREVIX_KEYSTORE")
            if (keystore.isNullOrEmpty() || !file(keystore).exists()) {
                throw GradleException("Falta la clave de firma de TREVIX (TREVIX_KEYSTORE).")
            }
            storeFile = file(keystore)
            storePassword = System.getenv("TREVIX_KEYSTORE_PASSWORD")
            keyAlias = "trevix"
            keyPassword = System.getenv("TREVIX_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {'''
src = sub(r"buildTypes\s*\{", signing, src, "la firma")
src = sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', src,
          "la firma de release")

src = src.rstrip() + '''

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
'''
kts.write_text(src, encoding="utf-8")
print(src)
