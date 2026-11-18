#!/usr/bin/env python3
"""Genera iconos alternativos para iOS (Assets + PNG sueltos) y Android (mipmap + adaptive correcto).

Uso (desde mobile/):
  python tool/prepare_alternate_icons.py --ios ios
  python tool/prepare_alternate_icons.py --android android
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "assets" / "icon"

# id → (archivo fuente, nombre iOS CFBundleAlternateIcons, etiqueta Android activity-alias)
ICONS = [
    ("wave", "icon_wave.png", "AppIconWave", "MainActivityWave"),
    ("heart", "icon_heart.png", "AppIconHeart", "MainActivityHeart"),
    ("messages", "icon_messages.png", "AppIconMessages", "MainActivityMessages"),
    ("mark", "icon_mark.png", "AppIconMark", "MainActivityMark"),
]

# Tamaños iOS para appiconset + PNG sueltos del bundle (CFBundleIconFiles).
IOS_SIZES = [
    ("carolyn@2x", 120),  # 60pt @2x
    ("carolyn@3x", 180),  # 60pt @3x
    ("ipad", 76),
    ("ipad@2x", 152),
    ("ipadpro@2x", 167),
    ("ios-marketing", 1024),
]

# PNG sueltos que exige setAlternateIconName (nombres sin extensión en Info.plist).
IOS_BUNDLE_PNG = [
    ("@2x", 120),
    ("@3x", 180),
]

ANDROID_MIPMAP = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def _load(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    bg = Image.new("RGBA", im.size, (152, 94, 255, 255))
    return Image.alpha_composite(bg, im).convert("RGB")


def _load_rgba(src: Path) -> Image.Image:
    """Foreground adaptive: conserva alpha sobre fondo transparente."""
    im = Image.open(src).convert("RGBA")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    return im


def _contents_ios(files: list[tuple[str, int, str]]) -> dict:
    images = []
    for filename, px, idiom in files:
        if px == 1024:
            images.append({"size": "1024x1024", "idiom": "ios-marketing", "filename": filename, "scale": "1x"})
        elif px == 120:
            images.append({"size": "60x60", "idiom": "iphone", "filename": filename, "scale": "2x"})
        elif px == 180:
            images.append({"size": "60x60", "idiom": "iphone", "filename": filename, "scale": "3x"})
        elif px == 76:
            images.append({"size": "76x76", "idiom": "ipad", "filename": filename, "scale": "1x"})
        elif px == 152:
            images.append({"size": "76x76", "idiom": "ipad", "filename": filename, "scale": "2x"})
        elif px == 167:
            images.append({"size": "83.5x83.5", "idiom": "ipad", "filename": filename, "scale": "2x"})
    return {"images": images, "info": {"version": 1, "author": "trevix"}}


def write_ios(ios_root: Path) -> None:
    assets = ios_root / "Runner" / "Assets.xcassets"
    runner = ios_root / "Runner"
    assets.mkdir(parents=True, exist_ok=True)
    runner.mkdir(parents=True, exist_ok=True)
    for key, file, ios_name, _ in ICONS:
        src = ICON_DIR / file
        if not src.exists():
            raise SystemExit(f"Falta {src}")
        im = _load(src)
        folder = assets / f"{ios_name}.appiconset"
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        listed: list[tuple[str, int, str]] = []
        for label, px in IOS_SIZES:
            name = f"Icon-{px}.png"
            im.resize((px, px), Image.Resampling.LANCZOS).save(folder / name, "PNG")
            listed.append((name, px, label))
        (folder / "Contents.json").write_text(json.dumps(_contents_ios(listed), indent=2), encoding="utf-8")
        # PNG sueltos en Runner/ para CFBundleIconFiles (setAlternateIconName).
        for suffix, px in IOS_BUNDLE_PNG:
            out = runner / f"{ios_name}{suffix}.png"
            im.resize((px, px), Image.Resampling.LANCZOS).save(out, "PNG")
            print(f"iOS bundle {out.name}")
        print(f"iOS {ios_name} → {folder}")


def _write_android_mipmaps(android_root: Path, key: str, im: Image.Image, fg: Image.Image) -> None:
    res = android_root / "app" / "src" / "main" / "res"
    for folder, px in ANDROID_MIPMAP.items():
        dest = res / folder
        dest.mkdir(parents=True, exist_ok=True)
        # Legacy / roundIcon: PNG plano con fondo.
        im.resize((px, px), Image.Resampling.LANCZOS).save(dest / f"ic_launcher_{key}.png", "PNG")
        # Foreground adaptive: nombre distinto para evitar referencia circular en anydpi-v26.
        fg.resize((px, px), Image.Resampling.LANCZOS).save(dest / f"ic_launcher_{key}_foreground.png", "PNG")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / f"ic_launcher_{key}.xml").write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_{key}_bg"/>
    <foreground android:drawable="@mipmap/ic_launcher_{key}_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    (anydpi / f"ic_launcher_{key}_round.xml").write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_{key}_bg"/>
    <foreground android:drawable="@mipmap/ic_launcher_{key}_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    colors = values / "ic_launcher_alt_colors.xml"
    entry = f'    <color name="ic_launcher_{key}_bg">#985EFF</color>\n'
    if colors.exists():
        text = colors.read_text(encoding="utf-8")
        if f"ic_launcher_{key}_bg" not in text:
            text = text.replace("</resources>", entry + "</resources>")
            colors.write_text(text, encoding="utf-8")
    else:
        colors.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + entry + "</resources>\n",
            encoding="utf-8",
        )


def _ensure_round_icon_on_aliases(manifest: Path) -> None:
    """Añade android:roundIcon a cada activity-alias de icono alternativo."""
    text = manifest.read_text(encoding="utf-8")
    changed = False
    for key, _, _, alias in ICONS:
        # Bloque del alias: insertar roundIcon si falta.
        pattern = rf'(<activity-alias\s+android:name="\.{alias}"[^>]*android:icon="@mipmap/ic_launcher_{key}")(?![^>]*roundIcon)'
        repl = rf'\1\n            android:roundIcon="@mipmap/ic_launcher_{key}_round"'
        new_text, n = re.subn(pattern, repl, text, count=1, flags=re.DOTALL)
        if n:
            text = new_text
            changed = True
            continue
        # Si el alias ya tiene roundIcon, ok; si icon apunta sin round, intentar otra forma.
        if f'.{alias}"' in text and f'ic_launcher_{key}_round' not in text.split(f'.{alias}"')[1][:400]:
            # Insert after android:icon line for this alias.
            icon_line = f'android:icon="@mipmap/ic_launcher_{key}"'
            if icon_line in text and f'android:roundIcon="@mipmap/ic_launcher_{key}_round"' not in text:
                text = text.replace(
                    icon_line,
                    icon_line + f'\n            android:roundIcon="@mipmap/ic_launcher_{key}_round"',
                    1,
                )
                changed = True
    if changed:
        manifest.write_text(text, encoding="utf-8")
        print("AndroidManifest: roundIcon en aliases")


def patch_android_manifest(android_root: Path) -> None:
    manifest = android_root / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        raise SystemExit(f"No está {manifest}")
    text = manifest.read_text(encoding="utf-8")
    if "MainActivityWave" in text:
        print("AndroidManifest ya tiene activity-alias de iconos")
        _ensure_round_icon_on_aliases(manifest)
        return
    aliases = []
    for key, _, _, alias in ICONS:
        aliases.append(
            f"""
        <activity-alias
            android:name=".{alias}"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_{key}"
            android:roundIcon="@mipmap/ic_launcher_{key}_round"
            android:label="TREVIX"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>"""
        )
    block = "\n".join(aliases) + "\n"
    if "</application>" not in text:
        raise SystemExit("AndroidManifest sin </application>")
    text = text.replace("</application>", block + "    </application>")
    manifest.write_text(text, encoding="utf-8")
    print("AndroidManifest: activity-alias de iconos añadidos")


def _ensure_default_round_icon(android_root: Path) -> None:
    """flutter_launcher_icons reciente solo escribe ic_launcher.xml; el alias default pide roundIcon."""
    anydpi = android_root / "app" / "src" / "main" / "res" / "mipmap-anydpi-v26"
    src = anydpi / "ic_launcher.xml"
    dest = anydpi / "ic_launcher_round.xml"
    if src.exists() and not dest.exists():
        shutil.copyfile(src, dest)
        print("Android ic_launcher_round.xml (copia del adaptive default)")
    # PNG legacy round por densidad (API < 26) si solo existe ic_launcher.png.
    res = android_root / "app" / "src" / "main" / "res"
    for folder in ANDROID_MIPMAP:
        base = res / folder / "ic_launcher.png"
        round_png = res / folder / "ic_launcher_round.png"
        if base.exists() and not round_png.exists():
            shutil.copyfile(base, round_png)


def write_android(android_root: Path) -> None:
    for key, file, _, _ in ICONS:
        src = ICON_DIR / file
        if not src.exists():
            raise SystemExit(f"Falta {src}")
        _write_android_mipmaps(android_root, key, _load(src), _load_rgba(src))
        print(f"Android ic_launcher_{key} (+ foreground / round)")
    _ensure_default_round_icon(android_root)
    patch_android_manifest(android_root)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--ios", type=Path, help="Carpeta ios/ del proyecto Flutter")
    p.add_argument("--android", type=Path, help="Carpeta android/ del proyecto Flutter")
    args = p.parse_args()
    if not args.ios and not args.android:
        p.error("Indica --ios y/o --android")
    if args.ios:
        write_ios(args.ios)
    if args.android:
        write_android(args.android)


if __name__ == "__main__":
    main()
