<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Models\RateLimit;

/**
 * Nombre del lugar a partir de coordenadas (al publicar con la ubicación actual), con OpenStreetMap Nominatim.
 * Las coordenadas se redondean a ~100 m antes de consultar: así se comparte la zona y no la dirección exacta,
 * y la caché (30 días) evita repetir consultas, como pide la política de uso de Nominatim.
 */
final class Geo
{
    private const ENDPOINT = 'https://nominatim.openstreetmap.org/reverse';
    private const CACHE_TTL = 30 * 24 * 3600;

    /** @return array{name:string, lat:float, lng:float} */
    public static function reverse(int $uid, mixed $lat, mixed $lng): array
    {
        if (!is_numeric($lat) || !is_numeric($lng) || abs((float) $lat) > 90 || abs((float) $lng) > 180) {
            throw new ActionError('La ubicación no es válida.', 422);
        }
        Guard::rateLimit('catalog_search', 'user:' . $uid, 'Hiciste demasiadas consultas. Espera {min} min.');
        RateLimit::hit('catalog_search', 'user:' . $uid);

        $lat = round((float) $lat, 3);
        $lng = round((float) $lng, 3);
        $url = self::ENDPOINT . '?' . http_build_query([
            'format' => 'jsonv2', 'lat' => $lat, 'lon' => $lng, 'zoom' => 14, 'addressdetails' => 1, 'accept-language' => 'es',
        ]);
        try {
            $data = HttpClient::getJson($url, self::CACHE_TTL);
        } catch (RuntimeException) {
            throw new ActionError('No se pudo obtener el nombre del lugar. Escríbelo tú.', 503);
        }
        $name = self::placeName((array) ($data['address'] ?? []));
        if ($name === '') {
            throw new ActionError('No encontramos un lugar con nombre aquí. Escríbelo tú.', 404);
        }
        return ['name' => $name, 'lat' => $lat, 'lng' => $lng];
    }

    /** «Barrio, Ciudad, País» con las partes disponibles (sin calle ni número). */
    private static function placeName(array $address): string
    {
        $pick = static function (array $keys) use ($address): string {
            foreach ($keys as $key) {
                if (!empty($address[$key]) && is_string($address[$key])) {
                    return trim($address[$key]);
                }
            }
            return '';
        };
        $parts = array_values(array_unique(array_filter([
            $pick(['suburb', 'neighbourhood', 'quarter', 'village', 'hamlet']),
            $pick(['city', 'town', 'municipality', 'county']),
            $pick(['country']),
        ])));
        return mb_substr(implode(', ', $parts), 0, 120);
    }
}
