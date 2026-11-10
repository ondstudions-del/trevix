<?php
declare(strict_types=1);

namespace Trevix\Services;

use GdImage;
use RuntimeException;
use Trevix\Core\Config;

/**
 * Fotos de perfil y portadas. Nunca se guarda el archivo original: se valida el MIME real,
 * se decodifica con GD, se recorta al tamaño final y se vuelve a codificar con un nombre aleatorio.
 * Así se descartan metadatos (EXIF, ubicación) y cualquier contenido incrustado.
 */
final class ImageUpload
{
    private const FOLDERS = [
        'avatar'           => 'uploads/avatars',
        'cover'            => 'uploads/covers',
        'community_avatar' => 'uploads/communities',
        'community_cover'  => 'uploads/communities',
        'song_cover'       => 'uploads/songs/covers',
        'event_cover'      => 'uploads/events',
        'group_avatar'     => 'uploads/groups',
        'group_cover'      => 'uploads/groups',
    ];

    /** Medidas finales (claves de app.uploads.profile) de cada tipo. */
    private const SIZES = [
        'avatar' => 'avatar', 'cover' => 'cover', 'community_avatar' => 'avatar', 'community_cover' => 'cover',
        'song_cover' => 'song_cover', 'event_cover' => 'event_cover', 'group_avatar' => 'avatar', 'group_cover' => 'cover',
    ];

    /**
     * Procesa el archivo del campo indicado. Devuelve la ruta relativa guardada o null si no se envió archivo.
     *
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeProfileImage(string $field, string $kind): ?string
    {
        if (!isset(self::FOLDERS[$kind])) {
            throw new \LogicException('Tipo de imagen desconocido: ' . $kind);
        }

        $file = $_FILES[$field] ?? null;
        if (!is_array($file) || !isset($file['error']) || is_array($file['error'])) {
            return null;
        }
        if ($file['error'] === UPLOAD_ERR_NO_FILE) {
            return null;
        }

        $limits = (array) Config::get('app.uploads.profile');
        $maxBytes = (int) $limits['max_bytes'];

        if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true) || (int) $file['size'] > $maxBytes) {
            throw new RuntimeException('La imagen supera el máximo de ' . round($maxBytes / 1048576) . ' MB.');
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file((string) $file['tmp_name'])) {
            throw new RuntimeException('No se pudo recibir la imagen. Inténtalo de nuevo.');
        }
        if (!extension_loaded('gd')) {
            throw new RuntimeException('El servidor no puede procesar imágenes en este momento.');
        }

        $path = (string) $file['tmp_name'];
        $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($path) ?: '';
        if (!in_array($mime, (array) Config::get('app.uploads.image.mimes'), true)) {
            throw new RuntimeException('Formato no permitido. Usa JPG, PNG, WEBP o GIF.');
        }

        $info = @getimagesize($path);
        if ($info === false || $info[0] < 1 || $info[1] < 1) {
            throw new RuntimeException('El archivo no es una imagen válida.');
        }
        if ($info[0] * $info[1] > (int) $limits['max_pixels']) {
            throw new RuntimeException('La imagen tiene demasiada resolución.');
        }

        $source = @imagecreatefromstring((string) file_get_contents($path));
        if (!$source instanceof GdImage) {
            throw new RuntimeException('No se pudo leer la imagen.');
        }

        if ($mime === 'image/jpeg') {
            $source = self::applyExifOrientation($source, $path);
        }

        $target = (array) $limits[self::SIZES[$kind]];
        $output = self::cropToFill($source, (int) $target['width'], (int) $target['height']);

        $folder = self::FOLDERS[$kind];
        $useWebp = function_exists('imagewebp');
        $name = bin2hex(random_bytes(16)) . ($useWebp ? '.webp' : '.jpg');
        $destination = BASE_PATH . '/' . $folder . '/' . $name;

        if (!is_dir(dirname($destination)) && !mkdir(dirname($destination), 0755, true)) {
            throw new RuntimeException('No se pudo guardar la imagen.');
        }

        $saved = $useWebp ? imagewebp($output, $destination, 85) : imagejpeg(self::flatten($output), $destination, 85);
        if (!$saved) {
            throw new RuntimeException('No se pudo guardar la imagen.');
        }

        return $folder . '/' . $name;
    }

    /** Borra una imagen guardada antes, solo si está dentro de las carpetas de perfil o de comunidades. */
    public static function delete(?string $relativePath): void
    {
        if ($relativePath === null || $relativePath === '') {
            return;
        }
        foreach (array_unique(self::FOLDERS) as $folder) {
            if (preg_match('#^' . preg_quote($folder, '#') . '/[a-f0-9]{32}\.(webp|jpg)$#', $relativePath)) {
                $file = BASE_PATH . '/' . $relativePath;
                if (is_file($file)) {
                    @unlink($file);
                }
                return;
            }
        }
    }

    /** Recorta al centro con la proporción de destino y escala sin agrandar más de lo necesario. */
    private static function cropToFill(GdImage $source, int $width, int $height): GdImage
    {
        $srcW = imagesx($source);
        $srcH = imagesy($source);
        $ratio = $width / $height;

        if ($srcW / $srcH > $ratio) {
            $cropH = $srcH;
            $cropW = (int) round($srcH * $ratio);
        } else {
            $cropW = $srcW;
            $cropH = (int) round($srcW / $ratio);
        }
        $srcX = (int) (($srcW - $cropW) / 2);
        $srcY = (int) (($srcH - $cropH) / 2);

        $outW = min($width, $cropW);
        $outH = max(1, (int) round($outW / $ratio));

        $output = imagecreatetruecolor($outW, $outH);
        imagealphablending($output, false);
        imagesavealpha($output, true);
        imagefill($output, 0, 0, imagecolorallocatealpha($output, 0, 0, 0, 127));
        imagecopyresampled($output, $source, 0, 0, $srcX, $srcY, $outW, $outH, $cropW, $cropH);

        return $output;
    }

    /** JPEG no admite transparencia: se compone sobre fondo oscuro. */
    public static function flatten(GdImage $image): GdImage
    {
        $flat = imagecreatetruecolor(imagesx($image), imagesy($image));
        imagefill($flat, 0, 0, imagecolorallocate($flat, 24, 24, 27));
        imagecopy($flat, $image, 0, 0, 0, 0, imagesx($image), imagesy($image));
        return $flat;
    }

    public static function applyExifOrientation(GdImage $image, string $path): GdImage
    {
        if (!function_exists('exif_read_data')) {
            return $image;
        }
        $exif = @exif_read_data($path);
        $angle = match ((int) ($exif['Orientation'] ?? 1)) {
            3 => 180,
            6 => -90,
            8 => 90,
            default => 0,
        };
        if ($angle === 0) {
            return $image;
        }
        $rotated = imagerotate($image, $angle, 0);
        if ($rotated instanceof GdImage) {
            return $rotated;
        }
        return $image;
    }
}
