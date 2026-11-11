<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;

/**
 * Archivos de audio de las canciones. El formato se identifica por el contenido (nunca por el nombre ni por
 * el MIME que envía el navegador) y la duración se calcula en el servidor:
 *  - MP3: tramas MPEG capa III; con cabecera Xing/Info o VBRI si la tasa es variable, si no por la tasa de bits.
 *  - M4A: contenedor MP4 con pista de sonido y sin pista de video (duración del átomo mvhd).
 * Se guarda con un nombre aleatorio en uploads/songs.
 */
final class AudioUpload
{
    public const FOLDER = 'uploads/songs';

    private const BITRATES_V1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
    private const BITRATES_V2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
    private const SAMPLE_RATES = [3 => [44100, 48000, 32000], 2 => [22050, 24000, 16000], 0 => [11025, 12000, 8000]];

    /**
     * @param array{error:int, tmp_name:string, size:int} $file de MediaUpload::collect
     * @return array{path:string, mime:string, size:int, duration:int}
     * @throws RuntimeException con un mensaje apto para el usuario.
     */
    public static function store(array $file): array
    {
        $rules = (array) Config::get('app.uploads.audio');
        $maxBytes = (int) $rules['max_bytes'];
        if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true) || $file['size'] > $maxBytes) {
            throw new RuntimeException(t('La canción puede pesar como máximo {n} MB.', ['n' => round($maxBytes / 1048576)]));
        }
        if ($file['error'] !== UPLOAD_ERR_OK || !is_uploaded_file($file['tmp_name'])) {
            throw new RuntimeException('No se pudo recibir el archivo de audio. Inténtalo de nuevo.');
        }

        $probe = self::probe($file['tmp_name']);
        if ($probe === null) {
            throw new RuntimeException('El archivo no es un MP3 o M4A válido.');
        }
        [$mime, $extension, $seconds] = $probe;
        $duration = (int) round($seconds);
        if ($duration < (int) $rules['min_seconds']) {
            throw new RuntimeException(t('La canción debe durar al menos {n} segundos.', ['n' => (int) $rules['min_seconds']]));
        }
        if ($duration > (int) $rules['max_seconds']) {
            throw new RuntimeException(t('La canción puede durar como máximo {n} minutos.', ['n' => intdiv((int) $rules['max_seconds'], 60)]));
        }

        $relative = self::FOLDER . '/' . bin2hex(random_bytes(16)) . '.' . $extension;
        $dir = BASE_PATH . '/' . self::FOLDER;
        if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
            throw new RuntimeException('No se pudo guardar la canción.');
        }
        if (!move_uploaded_file($file['tmp_name'], BASE_PATH . '/' . $relative)) {
            throw new RuntimeException('No se pudo guardar la canción.');
        }
        return ['path' => $relative, 'mime' => $mime, 'size' => (int) filesize(BASE_PATH . '/' . $relative), 'duration' => $duration];
    }

    /** Borra un archivo de audio, solo si su ruta tiene el formato que genera esta clase. */
    public static function delete(?string $relativePath): void
    {
        if ($relativePath === null || !preg_match('#^' . preg_quote(self::FOLDER, '#') . '/[a-f0-9]{32}\.(mp3|m4a)$#', $relativePath)) {
            return;
        }
        $file = BASE_PATH . '/' . $relativePath;
        if (is_file($file)) {
            @unlink($file);
        }
    }

    /**
     * Identifica el formato y la duración en segundos; null si no es un MP3 o M4A de audio válido.
     *
     * @return array{0:string, 1:string, 2:float}|null [mime, extensión, segundos]
     */
    public static function probe(string $path): ?array
    {
        $handle = @fopen($path, 'rb');
        if ($handle === false) {
            return null;
        }
        try {
            $size = (int) filesize($path);
            $head = (string) fread($handle, 12);
            if (strlen($head) === 12 && substr($head, 4, 4) === 'ftyp') {
                $seconds = self::mp4Duration($handle, $size);
                return $seconds !== null ? ['audio/mp4', 'm4a', $seconds] : null;
            }
            $seconds = self::mp3Duration($handle, $size);
            return $seconds !== null ? ['audio/mpeg', 'mp3', $seconds] : null;
        } finally {
            fclose($handle);
        }
    }

    // -------------------------------------------------------------------------
    // M4A
    // -------------------------------------------------------------------------

    /** @param resource $handle */
    private static function mp4Duration($handle, int $size): ?float
    {
        $info = ['duration' => null, 'sound' => false, 'video' => false];
        self::walkBoxes($handle, 0, $size, $info, 0);
        if (!$info['sound'] || $info['video'] || $info['duration'] === null) {
            return null;
        }
        return $info['duration'];
    }

    /**
     * Recorre los átomos del contenedor: baja por moov → trak → mdia, lee la duración de mvhd y el tipo
     * de cada pista de hdlr (soun = sonido, vide = video).
     *
     * @param resource $handle
     */
    private static function walkBoxes($handle, int $start, int $end, array &$info, int $depth): void
    {
        $pos = $start;
        $guard = 0;
        while ($pos + 8 <= $end && $guard++ < 4096) {
            fseek($handle, $pos);
            $header = (string) fread($handle, 8);
            if (strlen($header) < 8) {
                return;
            }
            $boxSize = unpack('N', substr($header, 0, 4))[1];
            $type = substr($header, 4, 4);
            $headerLength = 8;
            if ($boxSize === 1) {
                $large = (string) fread($handle, 8);
                if (strlen($large) < 8) {
                    return;
                }
                $parts = unpack('N2', $large);
                $boxSize = ($parts[1] << 32) | $parts[2];
                $headerLength = 16;
            } elseif ($boxSize === 0) {
                $boxSize = $end - $pos;
            }
            if ($boxSize < $headerLength || $pos + $boxSize > $end) {
                return;
            }

            if (in_array($type, ['moov', 'trak', 'mdia'], true) && $depth < 4) {
                self::walkBoxes($handle, $pos + $headerLength, $pos + $boxSize, $info, $depth + 1);
            } elseif ($type === 'mvhd') {
                $data = (string) fread($handle, 32);
                if (strlen($data) >= 20) {
                    if (ord($data[0]) === 1 && strlen($data) === 32) {
                        $timescale = unpack('N', substr($data, 20, 4))[1];
                        $parts = unpack('N2', substr($data, 24, 8));
                        $duration = ($parts[1] << 32) | $parts[2];
                    } else {
                        $timescale = unpack('N', substr($data, 12, 4))[1];
                        $duration = unpack('N', substr($data, 16, 4))[1];
                    }
                    if ($timescale > 0) {
                        $info['duration'] = $duration / $timescale;
                    }
                }
            } elseif ($type === 'hdlr') {
                $data = (string) fread($handle, 12);
                if (strlen($data) === 12) {
                    $handler = substr($data, 8, 4);
                    $info['sound'] = $info['sound'] || $handler === 'soun';
                    $info['video'] = $info['video'] || $handler === 'vide';
                }
            }
            $pos += $boxSize;
        }
    }

    // -------------------------------------------------------------------------
    // MP3
    // -------------------------------------------------------------------------

    /** @param resource $handle */
    private static function mp3Duration($handle, int $size): ?float
    {
        fseek($handle, 0);
        $head = (string) fread($handle, 10);
        $offset = 0;
        if (strlen($head) === 10 && str_starts_with($head, 'ID3')) {
            $tagSize = ((ord($head[6]) & 0x7F) << 21) | ((ord($head[7]) & 0x7F) << 14) | ((ord($head[8]) & 0x7F) << 7) | (ord($head[9]) & 0x7F);
            $offset = 10 + $tagSize + ((ord($head[5]) & 0x10) !== 0 ? 10 : 0);
        }
        if ($offset >= $size) {
            return null;
        }

        fseek($handle, $offset);
        $buffer = (string) fread($handle, 65536);
        $length = strlen($buffer);
        for ($i = 0; $i + 4 <= $length; $i++) {
            if (ord($buffer[$i]) !== 0xFF || (ord($buffer[$i + 1]) & 0xE0) !== 0xE0) {
                continue;
            }
            $frame = self::mp3Frame(substr($buffer, $i, 4));
            if ($frame === null) {
                continue;
            }
            // Una cabecera aislada puede ser casualidad: la siguiente trama debe empezar justo donde termina esta.
            $start = $offset + $i;
            fseek($handle, $start + $frame['length']);
            if (self::mp3Frame((string) fread($handle, 4)) === null) {
                continue;
            }

            fseek($handle, $start);
            $first = (string) fread($handle, 64);
            $xing = 4 + $frame['side_info'];
            $tag = substr($first, $xing, 4);
            if (($tag === 'Xing' || $tag === 'Info') && strlen($first) >= $xing + 12) {
                $flags = unpack('N', substr($first, $xing + 4, 4))[1];
                $frames = ($flags & 1) !== 0 ? unpack('N', substr($first, $xing + 8, 4))[1] : 0;
                if ($frames > 0) {
                    return $frames * $frame['samples'] / $frame['rate'];
                }
            }
            if (substr($first, 36, 4) === 'VBRI' && strlen($first) >= 54) {
                $frames = unpack('N', substr($first, 50, 4))[1];
                if ($frames > 0) {
                    return $frames * $frame['samples'] / $frame['rate'];
                }
            }

            $audioBytes = $size - $start;
            if ($size > 128) {
                fseek($handle, -128, SEEK_END);
                if (fread($handle, 3) === 'TAG') {
                    $audioBytes -= 128;
                }
            }
            return $audioBytes * 8 / ($frame['bitrate'] * 1000);
        }
        return null;
    }

    /** Cabecera de una trama MPEG capa III; null si no lo es. */
    private static function mp3Frame(string $bytes): ?array
    {
        if (strlen($bytes) < 4 || ord($bytes[0]) !== 0xFF || (ord($bytes[1]) & 0xE0) !== 0xE0) {
            return null;
        }
        $b1 = ord($bytes[1]);
        $b2 = ord($bytes[2]);
        $b3 = ord($bytes[3]);
        $version = ($b1 >> 3) & 0x03;      // 3 = MPEG 1, 2 = MPEG 2, 0 = MPEG 2.5, 1 = reservado
        $layer = ($b1 >> 1) & 0x03;        // 1 = capa III
        $bitrateIndex = ($b2 >> 4) & 0x0F;
        $rateIndex = ($b2 >> 2) & 0x03;
        if ($version === 1 || $layer !== 1 || $bitrateIndex === 0 || $bitrateIndex === 15 || $rateIndex === 3) {
            return null;
        }
        $mpeg1 = $version === 3;
        $bitrate = ($mpeg1 ? self::BITRATES_V1 : self::BITRATES_V2)[$bitrateIndex];
        $rate = self::SAMPLE_RATES[$version][$rateIndex];
        $samples = $mpeg1 ? 1152 : 576;
        $mono = (($b3 >> 6) & 0x03) === 3;
        return [
            'bitrate'   => $bitrate,
            'rate'      => $rate,
            'samples'   => $samples,
            'length'    => (int) floor(($samples / 8) * $bitrate * 1000 / $rate) + (($b2 >> 1) & 0x01),
            'side_info' => $mpeg1 ? ($mono ? 17 : 32) : ($mono ? 9 : 17),
        ];
    }
}
