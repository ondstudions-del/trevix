# Arreglo inmediato · migración 041 (avatar_caption)

## Síntoma

- App al iniciar sesión: `Unknown column 'avatar_caption' in 'SELECT'`
- Web con sesión: error **500** en la portada (misma consulta de usuario)

El **código en Hostinger ya es reciente**, pero **MySQL no tiene la migración 041**.

## Opción A · phpMyAdmin (≈ 2 min)

1. Hostinger → **Bases de datos** → **phpMyAdmin** → base de **TREVIX** (`u762375443_trevix` o similar).
2. Pestaña **SQL** → pega y ejecuta el contenido de:

   `database/migrations/041_profile_photos.sql`

3. Prueba login en la app y recarga la web (o borra cookies de `treviix.app`).

## Opción B · un solo PHP (recomendado)

El código real vive en **`ond-s.com/public_html/trevix`** (treviix.app solo usa `_gateway.php`).

1. Hostinger → **trevix.ond-s.com** → File Manager → carpeta **`trevix`**.
2. Sube **`_migrate_041_portable.php`** del repositorio (un único archivo).
3. Abre:

   ```
   https://treviix.app/_migrate_041_portable.php?t=cl041-e893db6921fd16fd694d0b8d74e41b7fc85e76ea6982bf32feff55fb06674206
   ```

## Opción C · script con SQL en disco

1. En la carpeta **`trevix`** (ond-s), sube:
   - `_migrate_041.php`
   - `database/migrations/041_profile_photos.sql`
2. Abre en el navegador:

   ```
   https://treviix.app/_migrate_041.php?t=cl041-e893db6921fd16fd694d0b8d74e41b7fc85e76ea6982bf32feff55fb06674206
   ```

   Debe terminar en `DONE` (el script se borra solo).

## Después

Si usas LiveKit u otras funciones nuevas, ejecuta también:

- `_migrate_040.php` (comentarios + PayPal)
- `_migrate_042.php` (LiveKit)

Sus tokens están en cada `_migrate_*.php` del repositorio.