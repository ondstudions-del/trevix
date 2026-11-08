<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\RateLimit;

/**
 * GIF y stickers de GIPHY para comentarios y mensajes. La clave de la API vive solo en el servidor
 * (config/local.php → app.services.giphy.api_key): el navegador y la app buscan a través de TREVIX.
 *
 * Al comentar o enviar un mensaje solo se recibe el id y el tipo: el GIF se vuelve a pedir a GIPHY por su
 * id y se guardan su URL (siempre de media*.giphy.com), tamaño y título. Nunca se guarda una URL enviada
 * por el cliente.
 */
final class Giphy
{
    public const KINDS = ['gif' => 'gifs', 'sticker' => 'stickers'];

    private const API = 'https://api.giphy.com/v1';
    private const PAGE = 24;

    public static function enabled(): bool
    {
        return self::key() !== '';
    }

    /**
     * Búsqueda (o tendencias si no hay texto) de GIF o stickers.
     *
     * @return array{items: list<array>, next: ?int}
     */
    public static function search(int $uid, string $kind, string $term, int $offset): array
    {
        if (!self::enabled()) {
            throw new ActionError('Los GIF no están disponibles en este momento.', 503);
        }
        if (!isset(self::KINDS[$kind])) {
            throw new ActionError('Tipo no válido.', 400);
        }
        Guard::rateLimit('catalog_search', 'user:' . $uid, 'Hiciste demasiadas búsquedas. Espera {min} min.');
        RateLimit::hit('catalog_search', 'user:' . $uid);

        $term = mb_substr(trim($term), 0, 50);
        $offset = max(0, min(4999 - self::PAGE, $offset));
        $query = [
            'api_key' => self::key(),
            'limit'   => self::PAGE,
            'offset'  => $offset,
            'rating'  => (string) Config::get('app.services.giphy.rating', 'pg-13'),
        ];
        $url = $term === ''
            ? self::API . '/' . self::KINDS[$kind] . '/trending?' . http_build_query($query)
            : self::API . '/' . self::KINDS[$kind] . '/search?' . http_build_query($query + ['q' => $term, 'lang' => (string) Config::get('app.services.giphy.lang', 'es')]);
        try {
            $data = HttpClient::getJson($url, (int) Config::get('app.services.cache_ttl', 600));
        } catch (RuntimeException) {
            throw new ActionError('No se pudo conectar con GIPHY. Inténtalo de nuevo.', 502);
        }
        $items = [];
        foreach ((array) ($data['data'] ?? []) as $row) {
            $gif = self::shape($row, $kind);
            if ($gif !== null) {
                $items[] = $gif;
            }
        }
        $total = (int) ($data['pagination']['total_count'] ?? 0);
        $next = $offset + self::PAGE;
        return ['items' => $items, 'next' => count($data['data'] ?? []) >= self::PAGE && $next < min($total, 4999) ? $next : null];
    }

    /**
     * GIF elegido al comentar o enviar un mensaje: se comprueba en GIPHY por su id.
     *
     * @return array{gif_id:string, gif_kind:string, gif_url:string, gif_width:int, gif_height:int, gif_title:?string}|null
     *         null si no se eligió ninguno.
     */
    public static function resolve(string $id, string $kind): ?array
    {
        $id = trim($id);
        if ($id === '') {
            return null;
        }
        if (!self::enabled()) {
            throw ActionError::field('gif', 'Los GIF no están disponibles en este momento.');
        }
        if (!preg_match('/^[A-Za-z0-9]{1,64}$/', $id)) {
            throw ActionError::field('gif', 'Ese GIF no es válido.');
        }
        $kind = isset(self::KINDS[$kind]) ? $kind : 'gif';
        try {
            $data = HttpClient::getJson(self::API . '/gifs/' . $id . '?' . http_build_query(['api_key' => self::key()]), 3600);
        } catch (RuntimeException) {
            throw ActionError::field('gif', 'No se pudo comprobar el GIF en GIPHY. Inténtalo de nuevo.');
        }
        $gif = self::shape($data['data'] ?? null, $kind);
        if ($gif === null || $gif['id'] !== $id) {
            throw ActionError::field('gif', 'Ese GIF ya no está disponible.');
        }
        return [
            'gif_id'     => $gif['id'],
            'gif_kind'   => $kind,
            'gif_url'    => $gif['url'],
            'gif_width'  => $gif['width'],
            'gif_height' => $gif['height'],
            'gif_title'  => $gif['title'] !== '' ? mb_substr($gif['title'], 0, 140) : null,
        ];
    }

    /** Campos gif_* de una fila (comentario o mensaje) para mostrar; null si no lleva GIF. */
    public static function fromRow(array $row): ?array
    {
        if (empty($row['gif_id']) || empty($row['gif_url']) || !self::allowedUrl((string) $row['gif_url'])) {
            return null;
        }
        return [
            'id'     => (string) $row['gif_id'],
            'kind'   => $row['gif_kind'] === 'sticker' ? 'sticker' : 'gif',
            'url'    => (string) $row['gif_url'],
            'width'  => (int) $row['gif_width'],
            'height' => (int) $row['gif_height'],
            'title'  => (string) ($row['gif_title'] ?? ''),
        ];
    }

    /** @return array{id:string, kind:string, title:string, url:string, width:int, height:int, preview:string}|null */
    private static function shape(mixed $row, string $kind): ?array
    {
        if (!is_array($row) || !is_string($row['id'] ?? null) || !is_array($row['images'] ?? null)) {
            return null;
        }
        $full = $row['images']['fixed_width'] ?? null;
        if (!is_array($full)) {
            return null;
        }
        $url = (string) ($full['webp'] ?? $full['url'] ?? '');
        $width = (int) ($full['width'] ?? 0);
        $height = (int) ($full['height'] ?? 0);
        if (!self::allowedUrl($url) || $width < 1 || $height < 1 || $width > 2000 || $height > 2000) {
            return null;
        }
        $small = $row['images']['fixed_width_small'] ?? $row['images']['fixed_height_small'] ?? [];
        $preview = is_array($small) ? (string) ($small['webp'] ?? $small['url'] ?? '') : '';
        return [
            'id'      => $row['id'],
            'kind'    => $kind,
            'title'   => trim((string) ($row['title'] ?? '')),
            'url'     => $url,
            'width'   => $width,
            'height'  => $height,
            'preview' => self::allowedUrl($preview) ? $preview : $url,
        ];
    }

    private static function allowedUrl(string $url): bool
    {
        return strlen($url) <= 500 && preg_match('#^https://(media\d*|i)\.giphy\.com/[A-Za-z0-9/_.\-?=&%]+$#', $url) === 1;
    }

    private static function key(): string
    {
        return (string) Config::get('app.services.giphy.api_key', '');
    }
}
