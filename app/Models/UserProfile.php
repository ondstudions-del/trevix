<?php
declare(strict_types=1);

namespace Trevix\Models;

use Throwable;

/** Datos personales del perfil (ciudades, situación sentimental, género, intereses, enlaces, contactos) y su canción. */
final class UserProfile extends Model
{
    public const RELATIONSHIP = [
        'single'          => 'Soltero/a',
        'in_relationship' => 'En una relación',
        'engaged'         => 'Comprometido/a',
        'married'         => 'Casado/a',
        'civil_union'     => 'En unión civil',
        'open'            => 'En una relación abierta',
        'complicated'     => 'Es complicado',
        'separated'       => 'Separado/a',
        'divorced'        => 'Divorciado/a',
        'widowed'         => 'Viudo/a',
    ];

    public const GENDERS = ['female' => 'Mujer', 'male' => 'Hombre', 'nonbinary' => 'No binario', 'other' => 'Otro'];

    /** Quién ve ciudades, cumpleaños, situación sentimental, género y contactos. friends = se siguen mutuamente. */
    public const AUDIENCES = ['everyone' => 'Todos', 'followers' => 'Seguidores', 'friends' => 'Amigos', 'nobody' => 'Solo yo'];

    /** Tipos de contacto: el valor se valida según el tipo (usuario, correo, teléfono o enlace). */
    public const CONTACT_TYPES = [
        'instagram' => 'Instagram',
        'tiktok'    => 'TikTok',
        'x'         => 'X',
        'facebook'  => 'Facebook',
        'youtube'   => 'YouTube',
        'snapchat'  => 'Snapchat',
        'twitch'    => 'Twitch',
        'linkedin'  => 'LinkedIn',
        'telegram'  => 'Telegram',
        'whatsapp'  => 'WhatsApp',
        'email'     => 'Correo',
        'phone'     => 'Teléfono',
    ];

    public const MAX_INTERESTS = 15;
    public const MAX_LINKS = 5;
    public const MAX_CONTACTS = 10;

    /** @return array<string, mixed> datos completos (con valores por defecto si aún no hay fila) */
    public static function forUser(int $userId): array
    {
        $row = self::fetchOne('SELECT * FROM user_profiles WHERE user_id = ? LIMIT 1', [$userId]);
        $interests = self::fetchAll(
            'SELECT label FROM user_interests WHERE user_id = ? ORDER BY position, label',
            [$userId]
        );
        return [
            'city'                => $row['city'] ?? null,
            'hometown'            => $row['hometown'] ?? null,
            'relationship_status' => $row['relationship_status'] ?? null,
            'gender'              => $row['gender'] ?? null,
            'links'               => self::decodeList($row['links'] ?? null),
            'contacts'            => self::decodeList($row['contacts'] ?? null),
            'details_audience'    => $row['details_audience'] ?? 'everyone',
            'show_birth_year'     => !empty($row['show_birth_year']),
            'interests'           => array_column($interests, 'label'),
            'song'                => isset($row['song_start'])
                ? (Song::cardsFor([(int) ($row['song_id'] ?? 0)])[(int) ($row['song_id'] ?? 0)] ?? Song::unavailable((int) ($row['song_id'] ?? 0)))
                    + ['start' => (int) $row['song_start']]
                : null,
        ];
    }

    /**
     * Guarda los datos personales (sin la canción). $data ya viene validado por ProfileDetailsService.
     *
     * @param array{city:?string, hometown:?string, relationship_status:?string, gender:?string, links:list<array>,
     *              contacts:list<array>, details_audience:string, show_birth_year:bool, interests:list<string>} $data
     */
    public static function saveDetails(int $userId, array $data): void
    {
        $db = self::db();
        $db->beginTransaction();
        try {
            self::execute(
                'INSERT INTO user_profiles (user_id, city, city_key, hometown, hometown_key, relationship_status, gender,
                     links, contacts, details_audience, show_birth_year)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE city = VALUES(city), city_key = VALUES(city_key), hometown = VALUES(hometown),
                     hometown_key = VALUES(hometown_key), relationship_status = VALUES(relationship_status),
                     gender = VALUES(gender), links = VALUES(links), contacts = VALUES(contacts),
                     details_audience = VALUES(details_audience), show_birth_year = VALUES(show_birth_year)',
                [
                    $userId,
                    $data['city'], $data['city'] !== null ? self::key($data['city']) : null,
                    $data['hometown'], $data['hometown'] !== null ? self::key($data['hometown']) : null,
                    $data['relationship_status'], $data['gender'],
                    $data['links'] !== [] ? json_encode($data['links'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
                    $data['contacts'] !== [] ? json_encode($data['contacts'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
                    $data['details_audience'], $data['show_birth_year'] ? 1 : 0,
                ]
            );
            self::execute('DELETE FROM user_interests WHERE user_id = ?', [$userId]);
            foreach (array_values($data['interests']) as $i => $label) {
                self::execute(
                    'INSERT IGNORE INTO user_interests (user_id, interest_key, label, position) VALUES (?, ?, ?, ?)',
                    [$userId, self::key($label), $label, $i]
                );
            }
            $db->commit();
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
    }

    /** Canción del perfil; null la quita. */
    public static function setSong(int $userId, ?int $songId, ?int $start): void
    {
        self::execute(
            'INSERT INTO user_profiles (user_id, song_id, song_start) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE song_id = VALUES(song_id), song_start = VALUES(song_start)',
            [$userId, $songId, $songId !== null ? $start : null]
        );
    }

    /** Texto comparable: minúsculas, sin acentos ni signos, espacios simples («Bogotá D.C.» → «bogota d c»). */
    public static function key(string $text): string
    {
        $text = mb_strtolower(trim($text));
        if (class_exists(\Normalizer::class)) {
            $text = (string) preg_replace('/\p{Mn}+/u', '', (string) \Normalizer::normalize($text, \Normalizer::FORM_D));
        } else {
            $text = strtr($text, ['á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a', 'ã' => 'a', 'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
                'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i', 'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o', 'õ' => 'o',
                'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u', 'ñ' => 'n', 'ç' => 'c']);
        }
        $text = trim((string) preg_replace('/[^\p{L}\p{N}]+/u', ' ', $text));
        return mb_substr($text, 0, 80);
    }

    private static function decodeList(?string $json): array
    {
        if ($json === null || $json === '') {
            return [];
        }
        $list = json_decode($json, true);
        return is_array($list) && array_is_list($list) ? $list : [];
    }
}
