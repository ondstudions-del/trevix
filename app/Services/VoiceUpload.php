<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;

/**
 * Notas de voz de los mensajes. El formato se identifica por el contenido y la duración se calcula en el
 * servidor (nunca se confía en el nombre, el MIME ni la duración que envía el cliente):
 *  - WAV PCM de 16 bits (lo graba el navegador): duración = tamaño de datos / bytes por segundo.
 *  - M4A/AAC (lo graba la app de iOS) y MP3: AudioUpload::probe.
 * Se guarda con un nombre aleatorio en uploads/messages (lo borra MediaUpload::delete con el mensaje).
 */
final class VoiceUpload
{
    /**
     * @param array{error:int, tmp_name:string, size:int} $file de MediaUpload::collect
     * @return array{path:string, mime_type:string, duration:int}
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function store(array $file): array
    {
        $rules = (array) Config::get('app.uploads.voice');
        $maxBytes = (int) $rules['max_bytes'];
        if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true) || $file['size'] > $maxBytes) {
            throw new RuntimeException('La nota de voz puede pesar como máximo ' . round($maxBytes / 1048576) . ' MB.');
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new RuntimeException('No se pudo recibir la nota de voz. Inténtalo de nuevo.');
        }

        $probe = self::wav($file['tmp_name']) ?? AudioUpload::probe($file['tmp_name']);
        if ($probe === null) {
            throw new RuntimeException('La nota de voz no tiene un formato válido (WAV, M4A o MP3).');
        }
        [$mime, $extension, $seconds] = $probe;
        $duration = (int) round($seconds);
        if ($duration < (int) $rules['min_seconds']) {
            throw new RuntimeException('La nota de voz es demasiado corta.');
        }
        if ($duration > (int) $rules['max_seconds']) {
            throw new RuntimeException('La nota de voz puede durar como máximo ' . intdiv((int) $rules['max_seconds'], 60) . ' minutos.');
        }

        $relative = MediaUpload::MESSAGE_FOLDER . '/' . bin2hex(random_bytes(16)) . '.' . $extension;
        $dir = BASE_PATH . '/' . MediaUpload::MESSAGE_FOLDER;
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            throw new RuntimeException('No se pudo guardar la nota de voz.');
        }
        if (!move_uploaded_file($file['tmp_name'], BASE_PATH . '/' . $relative)) {
            throw new RuntimeException('No se pudo guardar la nota de voz.');
        }
        return ['path' => $relative, 'mime_type' => $mime, 'duration' => $duration];
    }

    /**
     * WAV PCM de 16 bits, mono o estéreo, de 8 a 48 kHz.
     *
     * @return array{0:string, 1:string, 2:float}|null [mime, extensión, segundos]
     */
    private static function wav(string $path): ?array
    {
        $handle = @fopen($path, 'rb');
        if ($handle === false) {
            return null;
        }
        try {
            $head = (string) fread($handle, 12);
            if (strlen($head) < 12 || !str_starts_with($head, 'RIFF') || substr($head, 8, 4) !== 'WAVE') {
                return null;
            }
            $size = (int) filesize($path);
            $format = null;
            $pos = 12;
            for ($guard = 0; $pos + 8 <= $size && $guard < 64; $guard++) {
                fseek($handle, $pos);
                $chunk = (string) fread($handle, 8);
                if (strlen($chunk) < 8) {
                    return null;
                }
                $id = substr($chunk, 0, 4);
                $length = unpack('V', substr($chunk, 4, 4))[1];
                if ($id === 'fmt ') {
                    $fmt = (string) fread($handle, 16);
                    if (strlen($fmt) < 16) {
                        return null;
                    }
                    $format = unpack('vcodec/vchannels/Vrate/Vbyterate/valign/vbits', $fmt);
                } elseif ($id === 'data') {
                    if ($format === null || $format['codec'] !== 1 || $format['bits'] !== 16
                        || $format['channels'] < 1 || $format['channels'] > 2 || $format['rate'] < 8000 || $format['rate'] > 48000) {
                        return null;
                    }
                    $bytesPerSecond = $format['rate'] * $format['channels'] * 2;
                    $dataBytes = min($length, $size - $pos - 8);
                    return $dataBytes > 0 ? ['audio/wav', 'wav', $dataBytes / $bytesPerSecond] : null;
                }
                $pos += 8 + $length + ($length % 2);
            }
            return null;
        } finally {
            fclose($handle);
        }
    }
}
