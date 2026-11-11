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
 * - Video MP4/WEBM/MOV: se valida MIME real, firma del contenedor, tamaño y (en publicaciones) duración;
 *   se guarda con nombre aleatorio junto con su miniatura opcional.
 * Nunca se usa el nombre ni la extensión enviados por el cliente.
 */
final class MediaUpload
{
    public const FOLDER = 'uploads/posts';
    public const MESSAGE_FOLDER = 'uploads/messages';
    public const STORY_FOLDER = 'uploads/stories';
    /** Archivos del chat que no se sirven en público: cifrados de extremo a extremo y fotos de visualización única. */
    public const PROTECTED_FOLDER = 'storage/chat';

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
     * $poster: miniatura opcional del video; $imagesOnly: rechaza videos (hilos).
     *
     * @return list<array{type:string,path:string,mime_type:string,size_bytes:int,width:?int,height:?int,duration_seconds:?int,poster_path:?string}>
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeAll(array $files, ?array $poster = null, bool $imagesOnly = false): array
    {
        $max = (int) Config::get('app.uploads.max_files_per_post', 10);
        if (count($files) > $max) {
            throw new RuntimeException(t('Puedes adjuntar como máximo {n} archivos.', ['n' => $max]));
        }

        $stored = [];
        try {
            $videos = 0;
            foreach ($files as $file) {
                $item = self::store($file);
                $stored[] = $item;
                if ($item['type'] === 'video' && $imagesOnly) {
                    throw new RuntimeException('Los hilos solo llevan texto e imágenes.');
                }
                if ($item['type'] === 'video' && ++$videos > 1) {
                    throw new RuntimeException('Solo se permite un video por publicación.');
                }
            }
        } catch (RuntimeException $e) {
            foreach ($stored as $item) {
                self::delete($item['path']);
            }
            throw $e;
        }

        if ($poster !== null && $videos === 1) {
            foreach ($stored as $i => $item) {
                if ($item['type'] === 'video') {
                    $stored[$i] = self::attachPoster($item, $poster);
                }
            }
        }
        return $stored;
    }

    /**
     * Miniatura de un video (la genera la app con el primer fotograma). Es opcional: si no es una imagen
     * válida se descarta y el video se publica igual. Si el archivo no decía su tamaño, se toma el de la miniatura.
     */
    private static function attachPoster(array $video, array $poster, string $folder = self::FOLDER): array
    {
        try {
            $mime = self::checkReceived($poster);
            if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
                return $video;
            }
            $image = self::storeImage($poster, $mime, $folder, (int) Config::get('app.uploads.video_poster_max_side', 1080));
        } catch (RuntimeException) {
            return $video;
        }
        $video['poster_path'] = $image['path'];
        if ($video['width'] === null || $video['height'] === null) {
            $video['width'] = $image['width'];
            $video['height'] = $image['height'];
        }
        return $video;
    }

    /**
     * Imagen adjunta a un mensaje privado (una por mensaje, sin video).
     *
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeMessageImage(array $file, bool $protected = false): array
    {
        $mime = self::checkReceived($file);
        if (!in_array($mime, (array) Config::get('app.uploads.image.mimes'), true)) {
            throw new RuntimeException('Solo puedes enviar imágenes JPG, PNG, WEBP o GIF.');
        }
        $folder = $protected ? self::PROTECTED_FOLDER : self::MESSAGE_FOLDER;
        return self::storeImage($file, $mime, $folder, (int) Config::get('app.uploads.message_image_max_side', 1600));
    }

    /**
     * Video adjunto a un mensaje, con su miniatura opcional. Los de visualización única ($protected) se guardan
     * fuera de uploads/ y sin miniatura, para que no quede ningún fotograma a la vista.
     *
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeMessageVideo(array $file, ?array $poster = null, bool $protected = false): array
    {
        self::checkReceived($file);
        $folder = $protected ? self::PROTECTED_FOLDER : self::MESSAGE_FOLDER;
        $video = self::storeVideo(
            $file,
            $folder,
            (int) Config::get('app.chat.video_max_bytes', 64 * 1024 * 1024),
            (int) Config::get('app.chat.video_max_seconds', 180)
        );
        return $poster !== null && !$protected ? self::attachPoster($video, $poster, $folder) : $video;
    }

    /**
     * Archivo cifrado de extremo a extremo (foto, nota de voz o video que la app cifró antes de enviarlo). El
     * servidor no puede leerlo ni validarlo: solo comprueba que llegó y su tamaño, y lo guarda fuera de uploads/.
     *
     * @return array{path:string, mime_type:string, size_bytes:int}
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function storeEncrypted(array $file): array
    {
        self::checkReceived($file);
        $max = (int) Config::get('app.chat.e2ee_file_max', 16 * 1024 * 1024);
        if ($file['size'] < 29 || $file['size'] > $max) {
            throw new RuntimeException(t('El archivo puede pesar como máximo {n} MB.', ['n' => round($max / 1048576)]));
        }
        $relative = self::PROTECTED_FOLDER . '/' . bin2hex(random_bytes(16)) . '.bin';
        self::ensureFolder(self::PROTECTED_FOLDER);
        if (!move_uploaded_file($file['tmp_name'], BASE_PATH . '/' . $relative)) {
            throw new RuntimeException('No se pudo guardar el archivo.');
        }
        return ['path' => $relative, 'mime_type' => 'application/octet-stream', 'size_bytes' => (int) filesize(BASE_PATH . '/' . $relative)];
    }

    /** Archivo del chat que solo se entrega a los participantes (GET /messages/{id}/media). */
    public static function isProtected(?string $relativePath): bool
    {
        return $relativePath !== null && str_starts_with($relativePath, self::PROTECTED_FOLDER . '/');
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
        $folders = implode('|', array_map(static fn (string $f) => preg_quote($f, '#'), [self::FOLDER, self::MESSAGE_FOLDER, self::STORY_FOLDER, self::PROTECTED_FOLDER]));
        // wav, m4a y mp3: notas de voz de los mensajes (VoiceUpload). bin: archivos cifrados del chat.
        if ($relativePath === null || !preg_match('#^(' . $folders . ')/[a-f0-9]{32}\.(webp|jpg|gif|mp4|webm|mov|wav|m4a|mp3|bin)$#', $relativePath)) {
            return;
        }
        $file = BASE_PATH . '/' . $relativePath;
        if (is_file($file)) {
            @unlink($file);
        }
    }

    /**
     * Copia un adjunto de mensaje con un nombre nuevo (reenviar: cada mensaje tiene su archivo y borrar uno no
     * afecta al otro). null si la ruta no es válida o el archivo ya no existe.
     *
     * @return array{path:string, size_bytes:int}|null
     */
    public static function duplicate(string $relativePath): ?array
    {
        $folders = preg_quote(self::MESSAGE_FOLDER, '#') . '|' . preg_quote(self::PROTECTED_FOLDER, '#');
        if (!preg_match('#^(' . $folders . ')/[a-f0-9]{32}\.(webp|jpg|gif|mp4|webm|mov|wav|m4a|mp3|bin)$#', $relativePath, $m)) {
            return null;
        }
        $source = BASE_PATH . '/' . $relativePath;
        $target = $m[1] . '/' . bin2hex(random_bytes(16)) . '.' . $m[2];
        if (!is_file($source) || !@copy($source, BASE_PATH . '/' . $target)) {
            return null;
        }
        return ['path' => $target, 'size_bytes' => (int) filesize(BASE_PATH . '/' . $target)];
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
            return self::storeVideo(
                $file,
                self::FOLDER,
                (int) Config::get('app.uploads.video.max_bytes'),
                (int) Config::get('app.uploads.video.max_seconds', 300)
            );
        }
        throw new RuntimeException('Formato no permitido. Usa JPG, PNG, WEBP, GIF, MP4, WEBM o MOV.');
    }

    private static function storeImage(array $file, string $mime, string $folder, int $maxSide): array
    {
        $limits = (array) Config::get('app.uploads.image');
        $maxBytes = (int) $limits['max_bytes'];
        if ($file['size'] > $maxBytes) {
            throw new RuntimeException(t('Cada imagen puede pesar como máximo {n} MB.', ['n' => round($maxBytes / 1048576)]));
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

    /** $maxSeconds > 0: la duración se lee del propio archivo y se rechaza si no se puede leer o si la supera. */
    private static function storeVideo(array $file, string $folder, int $maxBytes, int $maxSeconds = 0): array
    {
        if ($file['size'] > $maxBytes) {
            throw new RuntimeException(t('El video puede pesar como máximo {n} MB.', ['n' => round($maxBytes / 1048576)]));
        }

        $container = self::videoContainer($file['tmp_name']);
        if ($container === null) {
            throw new RuntimeException('El video no es un MP4, WEBM o MOV válido.');
        }

        $probe = VideoProbe::probe($file['tmp_name']);
        if ($maxSeconds > 0) {
            if ($probe === null) {
                throw new RuntimeException('No se pudo leer la duración del video. Prueba con un MP4 o MOV.');
            }
            // Medio segundo de margen: los editores redondean y un video «de 5:00» puede durar 300,4 s.
            if ($probe['seconds'] > $maxSeconds + 0.5) {
                throw new RuntimeException(t('Los videos pueden durar como máximo {time}.', ['time' => self::minutes($maxSeconds)]));
            }
        }

        $relative = $folder . '/' . bin2hex(random_bytes(16)) . '.' . self::VIDEO_EXT[$container];
        self::ensureFolder($folder);
        if (!move_uploaded_file($file['tmp_name'], BASE_PATH . '/' . $relative)) {
            throw new RuntimeException('No se pudo guardar el video.');
        }
        $row = self::row('video', $relative, $container, self::dimension($probe['width'] ?? null), self::dimension($probe['height'] ?? null));
        $row['duration_seconds'] = $probe !== null ? (int) min(65535, max(1, round($probe['seconds']))) : null;
        return $row;
    }

    private static function minutes(int $seconds): string
    {
        return $seconds % 60 === 0
            ? tn(intdiv($seconds, 60), '{n} minuto', '{n} minutos')
            : t('{n} minutos', ['n' => sprintf('%d:%02d', intdiv($seconds, 60), $seconds % 60)]);
    }

    /** Ancho o alto razonable para guardar (SMALLINT UNSIGNED), o null. */
    private static function dimension(?int $value): ?int
    {
        return $value !== null && $value > 0 && $value <= 16384 ? $value : null;
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
            'type'             => $type,
            'path'             => $path,
            'mime_type'        => $mime,
            'size_bytes'       => (int) filesize(BASE_PATH . '/' . $path),
            'width'            => $width,
            'height'           => $height,
            'duration_seconds' => null,
            'poster_path'      => null,
        ];
    }
}
