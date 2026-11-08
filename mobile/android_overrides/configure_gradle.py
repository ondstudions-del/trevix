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

# Plugins que aún compilan contra un SDK antiguo: Flutter exige compilar contra el SDK 36 o posterior.
root = pathlib.Path("android/build.gradle.kts")
if not root.exists():
    sys.exit("No se encontró android/build.gradle.kts.")
root_src = root.read_text(encoding="utf-8")
force = '''subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.LibraryExtension && (android.compileSdk ?: 0) < 36) {
            android.compileSdk = 36
        }
    }
}

'''
idx = root_src.find("subprojects {")
if idx < 0:
    sys.exit("android/build.gradle.kts: no se encontró el bloque subprojects.")
root_src = root_src[:idx] + force + root_src[idx:]
root.write_text(root_src, encoding="utf-8")
print(root_src)

# La plantilla reserva 8 GB para Gradle; con el demonio de Kotlin y R8 el runner de GitHub se queda sin memoria.
props = pathlib.Path("android/gradle.properties")
lines = [l for l in props.read_text(encoding="utf-8").splitlines() if not l.startswith(("org.gradle.jvmargs", "kotlin.daemon.jvmargs"))]
lines += [
    "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError",
    "kotlin.daemon.jvmargs=-Xmx2g",
]
props.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(props.read_text(encoding="utf-8"))
