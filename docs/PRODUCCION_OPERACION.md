# Producción · despliegue y base de datos

## Arquitectura Hostinger

| Dominio | Carpeta real del PHP |
|---------|----------------------|
| `trevix.ond-s.com` | `domains/ond-s.com/public_html/trevix` |
| `treviix.app` | `domains/treviix.app/public_html` solo `_gateway.php` + `.htaccess` → **ejecuta el mismo árbol `trevix`** |

**TUS:** subir siempre contra **trevix.ond-s.com** → File Manager → carpeta `trevix` → copiar JWT.  
Base típica: `https://srv….hstgr.io/rest/…/api/tus` (sin `public_html` extra).

JSON de ejemplo: `%TEMP%\trevix-deploy\tus-onds-trevix.json` (`tus_base`, `auth`, `rest`).

## Arreglo obligatorio ahora (migración 041)

Síntoma app/web con sesión: `Unknown column 'avatar_caption'`.

1. **phpMyAdmin** → ejecutar `database/migrations/041_profile_photos.sql`, **o**
2. Subir `_migrate_041_portable.php` a **`public_html/trevix`** (ond-s) y abrir  
   `https://treviix.app/_migrate_041_portable.php?t=cl041-e893db6921fd16fd694d0b8d74e41b7fc85e76ea6982bf32feff55fb06674206`

Luego: `scripts/deploy-migrate-catchup.ps1` con JWT fresco (PHP endurecido + 040/042).

## Scripts

| Script | Uso |
|--------|-----|
| `deploy-migrate-catchup.ps1` | Migración 040–042 + `Config`, `Auth`, `ErrorHandler`, `functions.php` |
| `deploy-livekit-from-json.ps1` | LiveKit Alpha 2.4 |
| `deploy-livekit.ps1` | Igual con parámetros `-TusBase -Auth -Rest` |