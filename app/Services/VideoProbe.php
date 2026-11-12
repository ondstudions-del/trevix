<?php
declare(strict_types=1);

namespace Trevix\Services;

/**
 * Lee la duración y el tamaño de imagen de un video sin herramientas externas:
 * - MP4/MOV: átomos moov → mvhd (duración) y trak → tkhd (ancho, alto y giro) de la pista de video.
 * - WEBM: elementos EBML Segment → Info (Duration, TimecodeScale) y Tracks → Video (PixelWidth/Height).
 */
final class VideoProbe
{
    /**
     * @return array{seconds: float, width: ?int, height: ?int, audio?: bool}|null null si no se puede leer la duración.
     *   audio: el MP4/MOV tiene una pista de sonido (en WEBM no se informa).
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
            if (strlen($head) < 12) {
                return null;
            }
            if (str_starts_with($head, "\x1A\x45\xDF\xA3")) {
                return self::webm($handle, $size);
            }
            if (substr($head, 4, 4) === 'ftyp') {
                return self::mp4($handle, $size);
            }
            return null;
        } finally {
            fclose($handle);
        }
    }

    // -------------------------------------------------------------------------
    // MP4 / MOV
    // -------------------------------------------------------------------------

    /** @param resource $handle */
    private static function mp4($handle, int $size): ?array
    {
        $info = ['duration' => null, 'tracks' => [], 'track' => null];
        self::boxes($handle, 0, $size, $info, 0);
        if ($info['duration'] === null || $info['duration'] <= 0) {
            return null;
        }
        $width = $height = null;
        foreach ($info['tracks'] as $track) {
            if ($width === null && ($track['handler'] ?? '') === 'vide' && ($track['width'] ?? 0) > 0 && ($track['height'] ?? 0) > 0) {
                [$width, $height] = [$track['width'], $track['height']];
                if (!empty($track['rotated'])) {
                    [$width, $height] = [$height, $width];
                }
            }
        }
        $audio = in_array('soun', array_map(static fn (array $t): string => (string) ($t['handler'] ?? ''), $info['tracks']), true);
        return ['seconds' => (float) $info['duration'], 'width' => $width, 'height' => $height, 'audio' => $audio];
    }

    /** @param resource $handle */
    private static function boxes($handle, int $start, int $end, array &$info, int $depth): void
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
            $body = $pos + $headerLength;

            if ($type === 'trak' && $depth < 4) {
                $info['tracks'][] = [];
                $info['track'] = count($info['tracks']) - 1;
                self::boxes($handle, $body, $pos + $boxSize, $info, $depth + 1);
                $info['track'] = null;
            } elseif (in_array($type, ['moov', 'mdia'], true) && $depth < 4) {
                self::boxes($handle, $body, $pos + $boxSize, $info, $depth + 1);
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
            } elseif ($type === 'tkhd' && $info['track'] !== null) {
                $data = (string) fread($handle, 96);
                $version = strlen($data) > 0 ? ord($data[0]) : 0;
                // Versión 0: matriz en el byte 40 y tamaño en el 76; versión 1: 52 y 88 (16.16 de punto fijo).
                [$matrixAt, $sizeAt] = $version === 1 ? [52, 88] : [40, 76];
                if (strlen($data) >= $sizeAt + 8) {
                    $matrix = unpack('N2', substr($data, $matrixAt, 8));
                    $dims = unpack('N2', substr($data, $sizeAt, 8));
                    $info['tracks'][$info['track']]['width'] = (int) ($dims[1] >> 16);
                    $info['tracks'][$info['track']]['height'] = (int) ($dims[2] >> 16);
                    // a = 0 y b ≠ 0: la pista se muestra girada 90° o 270° (video vertical grabado con el móvil).
                    $info['tracks'][$info['track']]['rotated'] = $matrix[1] === 0 && $matrix[2] !== 0;
                }
            } elseif ($type === 'hdlr' && $info['track'] !== null) {
                $data = (string) fread($handle, 12);
                if (strlen($data) === 12) {
                    $info['tracks'][$info['track']]['handler'] = substr($data, 8, 4);
                }
            }
            $pos += $boxSize;
        }
    }

    // -------------------------------------------------------------------------
    // WEBM (Matroska)
    // -------------------------------------------------------------------------

    private const EBML_SEGMENT = 0x18538067;
    private const EBML_INFO = 0x1549A966;
    private const EBML_TIMECODE_SCALE = 0x2AD7B1;
    private const EBML_DURATION = 0x4489;
    private const EBML_TRACKS = 0x1654AE6B;
    private const EBML_TRACK_ENTRY = 0xAE;
    private const EBML_VIDEO = 0xE0;
    private const EBML_PIXEL_WIDTH = 0xB0;
    private const EBML_PIXEL_HEIGHT = 0xBA;
    private const EBML_CLUSTER = 0x1F43B675;

    /** @param resource $handle */
    private static function webm($handle, int $size): ?array
    {
        $state = ['scale' => 1000000, 'duration' => null, 'width' => null, 'height' => null];
        fseek($handle, 0);
        self::ebml($handle, 0, $size, $state, 0);
        if ($state['duration'] === null || $state['duration'] <= 0) {
            return null;
        }
        return [
            'seconds' => $state['duration'] * $state['scale'] / 1e9,
            'width'   => $state['width'],
            'height'  => $state['height'],
        ];
    }

    /** @param resource $handle */
    private static function ebml($handle, int $start, int $end, array &$state, int $depth): void
    {
        $pos = $start;
        $guard = 0;
        while ($pos < $end && $guard++ < 4096) {
            fseek($handle, $pos);
            $id = self::vint($handle, true);
            $len = self::vint($handle, false);
            if ($id === null || $len === null) {
                return;
            }
            $body = (int) ftell($handle);
            // Tamaño desconocido (Segment o Cluster en directo): el contenido llega hasta el final del padre.
            $stop = $len < 0 ? $end : min($end, $body + $len);

            switch ($id) {
                case self::EBML_SEGMENT:
                case self::EBML_INFO:
                case self::EBML_TRACKS:
                case self::EBML_TRACK_ENTRY:
                case self::EBML_VIDEO:
                    if ($depth < 6) {
                        self::ebml($handle, $body, $stop, $state, $depth + 1);
                    }
                    break;
                case self::EBML_CLUSTER:
                    // Los datos de imagen y sonido van en los Cluster: Info y Tracks siempre van antes.
                    return;
                case self::EBML_TIMECODE_SCALE:
                    $state['scale'] = self::uint($handle, $len) ?: 1000000;
                    break;
                case self::EBML_DURATION:
                    $raw = (string) fread($handle, max(0, $len));
                    if ($len === 4 && strlen($raw) === 4) {
                        $state['duration'] = unpack('G', $raw)[1];
                    } elseif ($len === 8 && strlen($raw) === 8) {
                        $state['duration'] = unpack('E', $raw)[1];
                    }
                    break;
                case self::EBML_PIXEL_WIDTH:
                    $state['width'] ??= self::uint($handle, $len);
                    break;
                case self::EBML_PIXEL_HEIGHT:
                    $state['height'] ??= self::uint($handle, $len);
                    break;
            }
            if ($len < 0) {
                return;
            }
            $pos = $body + $len;
        }
    }

    /**
     * Entero de longitud variable de EBML. Con $keepMarker devuelve el ID tal cual; si no, el tamaño
     * (-1 cuando es «desconocido», todos los bits de datos a 1).
     *
     * @param resource $handle
     */
    private static function vint($handle, bool $keepMarker): ?int
    {
        $first = fread($handle, 1);
        if ($first === false || $first === '') {
            return null;
        }
        $byte = ord($first);
        $length = 1;
        $mask = 0x80;
        while ($length <= 8 && ($byte & $mask) === 0) {
            $length++;
            $mask >>= 1;
        }
        if ($length > 8 || ($keepMarker && $length > 4)) {
            return null;
        }
        $value = $keepMarker ? $byte : ($byte & ($mask - 1));
        $allOnes = ($byte & ($mask - 1)) === $mask - 1;
        if ($length > 1) {
            $rest = (string) fread($handle, $length - 1);
            if (strlen($rest) !== $length - 1) {
                return null;
            }
            foreach (str_split($rest) as $c) {
                $value = ($value << 8) | ord($c);
                $allOnes = $allOnes && ord($c) === 0xFF;
            }
        }
        return !$keepMarker && $allOnes ? -1 : $value;
    }

    /** @param resource $handle */
    private static function uint($handle, int $len): ?int
    {
        if ($len < 1 || $len > 8) {
            return null;
        }
        $raw = (string) fread($handle, $len);
        if (strlen($raw) !== $len) {
            return null;
        }
        $value = 0;
        foreach (str_split($raw) as $c) {
            $value = ($value << 8) | ord($c);
        }
        return $value;
    }
}
