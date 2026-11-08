<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\User;
use Trevix\Models\UserProfile;

/** Datos personales y canción del perfil: validación, guardado y lo que ve cada persona según el público elegido. */
final class ProfileDetailsService
{
    private const HANDLE_TYPES = ['instagram', 'tiktok', 'x', 'snapchat', 'twitch', 'telegram', 'facebook', 'youtube', 'linkedin'];

    /**
     * Guarda los datos enviados. Los que no llegan conservan su valor; un texto vacío los borra.
     *
     * @param array<string, mixed> $input city, hometown, relationship_status, gender, interests (lista de textos),
     *        links (lista de {title, url}), contacts (lista de {type, value}), details_audience, show_birth_year, birth_date
     */
    public static function save(array $user, array $input): void
    {
        $uid = (int) $user['id'];
        $current = UserProfile::forUser($uid);
        $errors = [];

        $data = [
            'city'                => self::place($input, 'city', $current['city'], $errors),
            'hometown'            => self::place($input, 'hometown', $current['hometown'], $errors),
            'relationship_status' => self::choice($input, 'relationship_status', UserProfile::RELATIONSHIP, $current['relationship_status'], $errors),
            'gender'              => self::choice($input, 'gender', UserProfile::GENDERS, $current['gender'], $errors),
            'details_audience'    => self::choice($input, 'details_audience', UserProfile::AUDIENCES, $current['details_audience'], $errors) ?? 'everyone',
            'show_birth_year'     => array_key_exists('show_birth_year', $input) ? (bool) $input['show_birth_year'] : $current['show_birth_year'],
            'interests'           => array_key_exists('interests', $input) ? self::interests($input['interests'], $errors) : $current['interests'],
            'links'               => array_key_exists('links', $input) ? self::links($input['links'], $errors) : $current['links'],
            'contacts'            => array_key_exists('contacts', $input) ? self::contacts($input['contacts'], $errors) : $current['contacts'],
        ];

        $birth = null;
        if (array_key_exists('birth_date', $input)) {
            $birth = trim((string) $input['birth_date']);
            if ($birth === '') {
                $errors['birth_date'] = 'La fecha de nacimiento es obligatoria.';
            } elseif (($message = AccountRules::birthDate($birth)) !== null) {
                $errors['birth_date'] = $message;
            }
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        UserProfile::saveDetails($uid, $data);
        if ($birth !== null && $birth !== (string) ($user['birth_date'] ?? '')) {
            User::setBirthDate($uid, $birth);
        }
    }

    /** Canción del perfil: una de la biblioteca, con el inicio del fragmento de 30 s. */
    public static function setSong(int $uid, int $songId, int $start): array
    {
        $song = MusicService::resolveForUse($songId, $start, $uid);
        UserProfile::setSong($uid, $song['id'], $song['start']);
        return $song;
    }

    public static function removeSong(int $uid): void
    {
        UserProfile::setSong($uid, null, null);
    }

    /**
     * Lo que ve $viewerId del perfil de $owner. Enlaces, intereses y canción son públicos; el resto depende de
     * details_audience. La propia cuenta lo ve todo.
     *
     * @param array{following?:bool, follows_you?:bool}|null $relation relación de quien mira con la cuenta
     */
    public static function visibleTo(array $owner, array $details, int $viewerId, ?array $relation): array
    {
        $own = (int) $owner['id'] === $viewerId;
        $following = !empty($relation['following']);
        $allowed = $own || match ($details['details_audience']) {
            'everyone'  => true,
            'followers' => $following,
            'friends'   => $following && !empty($relation['follows_you']),
            default     => false,
        };

        $out = [
            'interests' => $details['interests'],
            'links'     => $details['links'],
            'song'      => $details['song'],
        ];
        if ($allowed) {
            $birth = (string) ($owner['birth_date'] ?? '');
            $out += [
                'city'                => $details['city'],
                'hometown'            => $details['hometown'],
                'relationship_status' => $details['relationship_status'],
                'relationship_label'  => UserProfile::RELATIONSHIP[$details['relationship_status'] ?? ''] ?? null,
                'gender'              => $details['gender'],
                'gender_label'        => UserProfile::GENDERS[$details['gender'] ?? ''] ?? null,
                'contacts'            => array_map(static fn (array $c): array => $c + [
                    'label' => UserProfile::CONTACT_TYPES[$c['type']] ?? $c['type'],
                    'url'   => self::contactUrl($c['type'], $c['value']),
                ], $details['contacts']),
                'birthday'            => preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $birth, $m) ? [
                    'day'   => (int) $m[3],
                    'month' => (int) $m[2],
                    'year'  => $own || $details['show_birth_year'] ? (int) $m[1] : null,
                ] : null,
            ];
        }
        if ($own) {
            $out += ['details_audience' => $details['details_audience'], 'show_birth_year' => $details['show_birth_year']];
        }
        return $out;
    }

    /** Opciones de los selectores de la app (claves y etiquetas en español). */
    public static function options(): array
    {
        $pairs = static fn (array $map): array => array_map(
            static fn (string $key, string $label): array => ['key' => $key, 'label' => $label],
            array_keys($map),
            array_values($map)
        );
        return [
            'relationship_status' => $pairs(UserProfile::RELATIONSHIP),
            'gender'              => $pairs(UserProfile::GENDERS),
            'details_audience'    => $pairs(UserProfile::AUDIENCES),
            'contact_types'       => $pairs(UserProfile::CONTACT_TYPES),
            'limits'              => [
                'interests' => UserProfile::MAX_INTERESTS,
                'links'     => UserProfile::MAX_LINKS,
                'contacts'  => UserProfile::MAX_CONTACTS,
            ],
        ];
    }

    /** Enlace que abre cada contacto (perfil de la red, correo, llamada o chat). */
    public static function contactUrl(string $type, string $value): ?string
    {
        if (str_starts_with($value, 'https://')) {
            return $value;
        }
        $digits = preg_replace('/[^0-9]/', '', $value);
        return match ($type) {
            'instagram' => 'https://instagram.com/' . rawurlencode($value),
            'tiktok'    => 'https://www.tiktok.com/@' . rawurlencode($value),
            'x'         => 'https://x.com/' . rawurlencode($value),
            'facebook'  => 'https://facebook.com/' . rawurlencode($value),
            'youtube'   => 'https://www.youtube.com/@' . rawurlencode($value),
            'snapchat'  => 'https://www.snapchat.com/add/' . rawurlencode($value),
            'twitch'    => 'https://www.twitch.tv/' . rawurlencode($value),
            'linkedin'  => 'https://www.linkedin.com/in/' . rawurlencode($value),
            'telegram'  => 'https://t.me/' . rawurlencode($value),
            'whatsapp'  => 'https://wa.me/' . $digits,
            'email'     => 'mailto:' . $value,
            'phone'     => 'tel:' . (str_starts_with($value, '+') ? '+' : '') . $digits,
            default     => null,
        };
    }

    private static function place(array $input, string $key, ?string $current, array &$errors): ?string
    {
        if (!array_key_exists($key, $input)) {
            return $current;
        }
        $value = trim((string) preg_replace('/\s+/u', ' ', (string) $input[$key]));
        if ($value === '') {
            return null;
        }
        if (mb_strlen($value) > 80 || preg_match('/[\p{C}<>]/u', $value) || UserProfile::key($value) === '') {
            $errors[$key] = 'Escribe un nombre de ciudad válido (hasta 80 caracteres).';
        }
        return $value;
    }

    private static function choice(array $input, string $key, array $allowed, ?string $current, array &$errors): ?string
    {
        if (!array_key_exists($key, $input)) {
            return $current;
        }
        $value = trim((string) $input[$key]);
        if ($value === '') {
            return null;
        }
        if (!isset($allowed[$value])) {
            $errors[$key] = 'Elige una opción de la lista.';
        }
        return $value;
    }

    /** @return list<string> */
    private static function interests(mixed $list, array &$errors): array
    {
        if (!is_array($list)) {
            $errors['interests'] = 'Envía los intereses como una lista.';
            return [];
        }
        $out = [];
        foreach ($list as $item) {
            $label = is_string($item) ? trim((string) preg_replace('/\s+/u', ' ', ltrim($item, '#'))) : '';
            if ($label === '') {
                continue;
            }
            if (mb_strlen($label) > 30 || preg_match('/[\p{C}<>]/u', $label) || UserProfile::key($label) === '') {
                $errors['interests'] = 'Cada interés debe tener hasta 30 caracteres, sin símbolos especiales.';
                return [];
            }
            $out[UserProfile::key($label)] ??= $label;
        }
        if (count($out) > UserProfile::MAX_INTERESTS) {
            $errors['interests'] = 'Puedes añadir hasta ' . UserProfile::MAX_INTERESTS . ' intereses.';
        }
        return array_values($out);
    }

    /** @return list<array{title:string, url:string}> */
    private static function links(mixed $list, array &$errors): array
    {
        if (!is_array($list)) {
            $errors['links'] = 'Envía los enlaces como una lista.';
            return [];
        }
        $out = [];
        foreach ($list as $item) {
            $url = AccountRules::normalizeWebsite(is_array($item) ? trim((string) ($item['url'] ?? '')) : '');
            $title = is_array($item) ? trim((string) preg_replace('/\s+/u', ' ', (string) ($item['title'] ?? ''))) : '';
            if ($url === '') {
                continue;
            }
            if (($message = AccountRules::website($url)) !== null) {
                $errors['links'] = $message;
                return [];
            }
            if (mb_strlen($title) > 40 || preg_match('/[\p{C}<>]/u', $title)) {
                $errors['links'] = 'El título de cada enlace puede tener hasta 40 caracteres.';
                return [];
            }
            $out[] = ['title' => $title !== '' ? $title : (string) parse_url($url, PHP_URL_HOST), 'url' => $url];
        }
        if (count($out) > UserProfile::MAX_LINKS) {
            $errors['links'] = 'Puedes añadir hasta ' . UserProfile::MAX_LINKS . ' enlaces.';
        }
        return $out;
    }

    /** @return list<array{type:string, value:string}> */
    private static function contacts(mixed $list, array &$errors): array
    {
        if (!is_array($list)) {
            $errors['contacts'] = 'Envía los contactos como una lista.';
            return [];
        }
        $out = [];
        foreach ($list as $item) {
            $type = is_array($item) ? (string) ($item['type'] ?? '') : '';
            $value = is_array($item) ? trim((string) ($item['value'] ?? '')) : '';
            if ($value === '') {
                continue;
            }
            if (!isset(UserProfile::CONTACT_TYPES[$type])) {
                $errors['contacts'] = 'Elige el tipo de cada contacto.';
                return [];
            }
            $clean = self::contactValue($type, $value);
            if ($clean === null) {
                $errors['contacts'] = 'Revisa el contacto de ' . UserProfile::CONTACT_TYPES[$type] . '.';
                return [];
            }
            $out[] = ['type' => $type, 'value' => $clean];
        }
        if (count($out) > UserProfile::MAX_CONTACTS) {
            $errors['contacts'] = 'Puedes añadir hasta ' . UserProfile::MAX_CONTACTS . ' contactos.';
        }
        return $out;
    }

    /** Valor normalizado del contacto, o null si no es válido para su tipo. */
    private static function contactValue(string $type, string $value): ?string
    {
        if ($type === 'email') {
            $value = mb_strtolower($value);
            return AccountRules::email($value) === null ? $value : null;
        }
        if ($type === 'phone' || $type === 'whatsapp') {
            if (!preg_match('/^\+?[0-9][0-9 ().-]{5,22}$/', $value)) {
                return null;
            }
            $digits = (string) preg_replace('/[^0-9]/', '', $value);
            return strlen($digits) >= 6 && strlen($digits) <= 15 ? (str_starts_with($value, '+') ? '+' : '') . $digits : null;
        }
        if (in_array($type, self::HANDLE_TYPES, true)) {
            if (preg_match('#^https?://#i', $value)) {
                return AccountRules::website($value) === null && str_starts_with(strtolower($value), 'https://') ? $value : null;
            }
            $handle = ltrim($value, '@');
            return preg_match('/^[A-Za-z0-9._-]{1,60}$/', $handle) ? $handle : null;
        }
        return null;
    }
}
