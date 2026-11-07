<?php
declare(strict_types=1);

namespace Trevix\Services;

use GdImage;
use RuntimeException;
use Trevix\Core\Config;

/**
 * Archivos adjuntos de publicaciones.
 * - Imágenes JPG/PNG/WEBP: se decodifican con GD, se reescalan y se vuelven a codificar (sin metadatos).
 * - GIF: se conservan tal cual para no perder la animación, tras validar MIME real y dimensiones.
 * - Video MP4/WEBM/MOV: se valida MIME real, firma del contenedor y tamaño; se guarda con nombre aleatorio.
 * Nunca se usa el nombre ni la extensión enviados por el cliente.
 */
final class MediaUpload
{
    public const FOLDER = 'uploads/posts';
    public const MESSAGE_FOLDER = 'uploads/messages';
    public const STORY_FOLDER = 'uploads/stories';

    private const VIDEO_EXT = ['video/mp4' => 'mp4', 'video/webm' => 'webm', 'video/quicktime' => 'mov'];

    /** Normaliza $_FILES[campo][] en una lista de archivos, ignorando los huecos vacíos. */
    public static function collect(string $field): array
    {
        $raw = $_FILES[$field] ?? null;
        if (!is_array($raw) || !isset($raw['error'])) {
            return [];
        }
        if (!is_array($raw['error'])) {
            $raw = array_map(static fn ($v) => [$v], $raw);
        }

        $files = [];
        foreach ($raw['error'] as $i => $error) {
            if ((int) $error === UPLOAD_ERR_NO_FILE) {
                continue;
            }
            $files[] = [
                'error'    => (int) $error,
                'tmp_name' => (string) ($raw['tmp_name'][$i] ?? ''),
                'size'     => (int) ($raw['size'][$i] ?? 0),
            ];
        }
        return $files;
    }

    /**
     * Valida y guarda todos los archivos. Si uno falla, borra los ya guardados y lanza la excepción.
     *
     * @return list<array{type:string,path:string,mime_type:string,size_bytes:int,width:?int,height:?int}>
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeAll(array $files): array
    {
        $max = (int) Config::get('app.uploads.max_files_per_post', 10);
        if (count($files) > $max) {
            throw new RuntimeException('Puedes adjuntar como máximo ' . $max . ' archivos.');
        }

        $stored = [];
        try {
            $videos = 0;
            foreach ($files as $file) {
                $item = self::store($file);
                if ($item['type'] === 'video' && ++$videos > 1) {
                    self::delete($item['path']);
                    throw new RuntimeException('Solo se permite un video por publicación.');
                }
                $stored[] = $item;
            }
        } catch (RuntimeException $e) {
            foreach ($stored as $item) {
                self::delete($item['path']);
            }
            throw $e;
        }
        return $stored;
    }

    /**
     * Imagen adjunta a un mensaje privado (una por mensaje, sin video).
     *
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeMessageImage(array $file): array
    {
        $mime = self::checkReceived($file);
        if (!in_array($mime, (array) Config::get('app.uploads.image.mimes'), true)) {
            throw new RuntimeException('Solo puedes enviar imágenes JPG, PNG, WEBP o GIF.');
        }
        return self::storeImage($file, $mime, self::MESSAGE_FOLDER, (int) Config::get('app.uploads.message_image_max_side', 1600));
    }

    /**
     * Imagen o video de una historia.
     *
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeStoryMedia(array $file): array
    {
        $mime = self::checkReceived($file);
        if (in_array($mime, (array) Config::get('app.uploads.image.mimes'), true)) {
            return self::storeImage($file, $mime, self::STORY_FOLDER, (int) Config::get('app.uploads.story_image_max_side', 1920));
        }
        if (in_array($mime, (array) Config::get('app.uploads.video.mimes'), true) || self::looksLikeVideo($file['tmp_name'])) {
            return self::storeVideo($file, self::STORY_FOLDER, (int) Config::get('app.uploads.story_video_max_bytes'));
        }
        throw new RuntimeException('Formato no permitido. Usa JPG, PNG, WEBP, GIF, MP4, WEBM o MOV.');
    }

    /** Borra un archivo adjunto, solo si su ruta tiene el formato que genera esta clase. */
    public static function delete(?string $relativePath): void
    {
        $folders = implode('|', array_map(static fn (string $f) => preg_quote($f, '#'), [self::FOLDER, self::MESSAGE_FOLDER, self::STORY_FOLDER]));
        if ($relativePath === null || !preg_match('#^(' . $folders . ')/[a-f0-9]{32}\.(webp|jpg|gif|mp4|webm|mov)$#', $relativePath)) {
            return;
        }
        $file = BASE_PATH . '/' . $relativePath;
        if (is_file($file)) {
            @unlink($file);
        }
    }

    /** Comprueba que el archivo llegó bien y devuelve su MIME real. */
    private static function checkReceived(array $file): string
    {
        if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true)) {
            throw new RuntimeException('Un archivo supera el tamaño máximo permitido por el servidor.');
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new RuntimeException('No se pudo recibir uno de los archivos. Inténtalo de nuevo.');
        }
        return (new \finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']) ?: '';
    }

    private static function store(array $file): array
    {
        $mime = self::checkReceived($file);
        if (in_array($mime, (array) Config::get('app.uploads.image.mimes'), true)) {
            return self::storeImage($file, $mime, self::FOLDER, (int) Config::get('app.uploads.post_image_max_side', 2048));
        }
        if (in_array($mime, (array) Config::get('app.uploads.video.mimes'), true) || self::looksLikeVideo($file['tmp_name'])) {
            return self::storeVideo($file, self::FOLDER, (int) Config::get('app.uploads.video.max_bytes'));
        }
        throw new RuntimeException('Formato no permitido. Usa JPG, PNG, WEBP, GIF, MP4, WEBM o MOV.');
    }

    private static function storeImage(array $file, string $mime, string $folder, int $maxSide): array
    {
        $limits = (array) Config::get('app.uploads.image');
        $maxBytes = (int) $limits['max_bytes'];
        if ($file['size'] > $maxBytes) {
            throw new RuntimeException('Cada imagen puede pesar como máximo ' . round($maxBytes / 1048576) . ' MB.');
        }

        $path = $file['tmp_name'];
        $info = @getimagesize($path);
        if ($info === false || $info[0] < 1 || $info[1] < 1) {
            throw new RuntimeException('Uno de los archivos no es una imagen válida.');
        }
        if ($info[0] * $info[1] > (int) $limits['max_pixels']) {
            throw new RuntimeException('Una de las imágenes tiene demasiada resolución.');
        }

        if ($mime === 'image/gif') {
            if (($info[2] ?? null) !== IMAGETYPE_GIF) {
                throw new RuntimeException('Uno de los archivos no es un GIF válido.');
            }
            $relative = $folder . '/' . bin2hex(random_bytes(16)) . '.gif';
            self::ensureFolder($folder);
            if (!move_uploaded_file($path, BASE_PATH . '/' . $relative)) {
                throw new RuntimeException('No se pudo guardar la imagen.');
            }
            return self::row('image', $relative, 'image/gif', $info[0], $info[1]);
        }

        if (!extension_loaded('gd')) {
            throw new RuntimeException('El servidor no puede procesar imágenes en este momento.');
        }
        $source = @imagecreatefromstring((string) file_get_contents($path));
        if (!$source instanceof GdImage) {
            throw new RuntimeException('No se pudo leer una de las imágenes.');
        }
        if ($mime === 'image/jpeg') {
            $source = ImageUpload::applyExifOrientation($source, $path);
        }

        $output = self::fit($source, $maxSide);
        $useWebp = function_exists('imagewebp');
        $relative = $folder . '/' . bin2hex(random_bytes(16)) . ($useWebp ? '.webp' : '.jpg');
        self::ensureFolder($folder);

        $destination = BASE_PATH . '/' . $relative;
        $saved = $useWebp ? imagewebp($output, $destination, 82) : imagejpeg(ImageUpload::flatten($output), $destination, 85);
        if (!$saved) {
            throw new RuntimeException('No se pudo guardar la imagen.');
        }
        return self::row('image', $relative, $useWebp ? 'image/webp' : 'image/jpeg', imagesx($output), imagesy($output));
    }

    private static function storeVideo(array $file, string $folder, int $maxBytes): array
    {
        if ($file['size'] > $maxBytes) {
            throw new RuntimeException('El video puede pesar como máximo ' . round($maxBytes / 1048576) . ' MB.');
        }

        $container = self::videoContainer($file['tmp_name']);
        if ($container === null) {
            throw new RuntimeException('El video no es un MP4, WEBM o MOV válido.');
        }

        $relative = $folder . '/' . bin2hex(random_bytes(16)) . '.' . self::VIDEO_EXT[$container];
        self::ensureFolder($folder);
        if (!move_uploaded_file($file['tmp_name'], BASE_PATH . '/' . $relative)) {
            throw new RuntimeException('No se pudo guardar el video.');
        }
        return self::row('video', $relative, $container, null, null);
    }

    private static function looksLikeVideo(string $path): bool
    {
        return self::videoContainer($path) !== null;
    }

    /** Identifica el contenedor por su firma binaria (no por la extensión). */
    private static function videoContainer(string $path): ?string
    {
        $head = (string) @file_get_contents($path, false, null, 0, 16);
        if (strlen($head) < 12) {
            return null;
        }
        if (str_starts_with($head, "\x1A\x45\xDF\xA3")) {
            return 'video/webm';
        }
        if (substr($head, 4, 4) !== 'ftyp') {
            return null;
        }
        $brand = substr($head, 8, 4);
        if ($brand === 'qt  ') {
            return 'video/quicktime';
        }
        // HEIC/AVIF también usan "ftyp": solo se aceptan marcas de video conocidas.
        $videoBrands = ['isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V ', 'M4VP', 'mmp4', 'dash', 'MSNV', 'f4v ', '3gp4', '3gp5', '3gp6'];
        return in_array($brand, $videoBrands, true) ? 'video/mp4' : null;
    }

    /** Reduce la imagen para que su lado mayor no supere $maxSide (nunca la agranda). */
    private static function fit(GdImage $source, int $maxSide): GdImage
    {
        $w = imagesx($source);
        $h = imagesy($source);
        $scale = min(1, $maxSide / max($w, $h));
        $outW = max(1, (int) round($w * $scale));
        $outH = max(1, (int) round($h * $scale));

        $output = imagecreatetruecolor($outW, $outH);
        imagealphablending($output, false);
        imagesavealpha($output, true);
        imagefill($output, 0, 0, imagecolorallocatealpha($output, 0, 0, 0, 127));
        imagecopyresampled($output, $source, 0, 0, 0, 0, $outW, $outH, $w, $h);
        return $output;
    }

    private static function ensureFolder(string $folder): void
    {
        $dir = BASE_PATH . '/' . $folder;
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            throw new RuntimeException('No se pudo guardar el archivo.');
        }
    }

    private static function row(string $type, string $path, string $mime, ?int $width, ?int $height): array
    {
        return [
            'type'       => $type,
            'path'       => $path,
            'mime_type'  => $mime,
            'size_bytes' => (int) filesize(BASE_PATH . '/' . $path),
            'width'      => $width,
            'height'     => $height,
        ];
    }
}
