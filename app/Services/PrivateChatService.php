<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Api\Present;
use Trevix\Core\ActionError;
use Trevix\Core\Session;
use Trevix\Models\Conversation;
use Trevix\Models\Message;
use Trevix\Models\PrivateChat;
use Trevix\Models\RateLimit;

/**
 * Chats privados: cada persona oculta los chats que quiera detrás de un PIN de 4 a 8 números. No salen en la bandeja,
 * la búsqueda, el contador de no leídos, los destinos para compartir ni el almacenamiento por chat, y sus avisos no
 * dicen quién escribió ni qué. Se abren escribiendo el PIN en el buscador de los chats, que devuelve un desbloqueo
 * firmado con el hash del PIN (caduca a las 2 horas y deja de valer al cambiar el PIN). Si se olvida el PIN, con la
 * contraseña de la cuenta se pueden exportar y después se vacían antes de crear uno nuevo.
 */
final class PrivateChatService
{
    public const PIN_PATTERN = '/^\d{4,8}$/';
    public const TOKEN_TTL = 2 * 60 * 60;
    public const EXPORT_LIMIT = 5000;

    private const PIN_LIMIT_MESSAGE = 'Demasiados intentos con el PIN. Inténtalo de nuevo en {min} min.';

    private const SESSION_KEY = 'private_chats';

    public static function validPin(string $pin): bool
    {
        return preg_match(self::PIN_PATTERN, $pin) === 1;
    }

    /** Web: el desbloqueo vive en la sesión hasta volver a la bandeja normal, cerrar los privados o caducar. */
    public static function webUnlocked(int $uid): bool
    {
        return self::validToken($uid, (string) Session::get(self::SESSION_KEY, ''));
    }

    public static function webUnlock(string $token): void
    {
        Session::set(self::SESSION_KEY, $token);
    }

    public static function webLock(): void
    {
        Session::forget(self::SESSION_KEY);
    }

    /** Desbloqueo para las próximas 2 horas, o null si la persona no tiene PIN. */
    public static function token(int $uid): ?string
    {
        $hash = PrivateChat::pinHash($uid);
        if ($hash === null) {
            return null;
        }
        $payload = $uid . '.' . (time() + self::TOKEN_TTL);
        return $payload . '.' . hash_hmac('sha256', $payload, $hash);
    }

    public static function validToken(int $uid, ?string $token): bool
    {
        $parts = explode('.', (string) $token);
        if (count($parts) !== 3 || (int) $parts[0] !== $uid || (int) $parts[1] < time()) {
            return false;
        }
        $hash = PrivateChat::pinHash($uid);
        return $hash !== null && hash_equals(hash_hmac('sha256', $parts[0] . '.' . $parts[1], $hash), $parts[2]);
    }

    /**
     * Lo escrito en el buscador de los chats: si es el PIN, devuelve el desbloqueo; si no, null sin delatar si hay
     * chats privados (los intentos fallidos cuentan y, al pasar el límite, el buscador deja de probarlos un rato).
     */
    public static function trySearch(int $uid, string $term): ?string
    {
        if (!self::validPin($term)) {
            return null;
        }
        $key = 'user:' . $uid;
        if (RateLimit::tooManyAttempts('private_pin', $key) || !PrivateChat::hasPin($uid)) {
            return null;
        }
        if (!PrivateChat::verify($uid, $term)) {
            RateLimit::hit('private_pin', $key);
            return null;
        }
        RateLimit::clear('private_pin', $key);
        return self::token($uid);
    }

    /** Desbloqueo con el PIN escrito en un diálogo (abrir un chat privado desde otro sitio, ajustes). */
    public static function unlock(int $uid, string $pin, string $field = 'pin'): string
    {
        $key = 'user:' . $uid;
        Guard::rateLimit('private_pin', $key, self::PIN_LIMIT_MESSAGE);
        if (!PrivateChat::hasPin($uid)) {
            throw ActionError::field($field, 'Aún no creaste el PIN de tus chats privados.');
        }
        if (!PrivateChat::verify($uid, $pin)) {
            RateLimit::hit('private_pin', $key);
            throw ActionError::field($field, 'El PIN no es correcto.');
        }
        RateLimit::clear('private_pin', $key);
        return (string) self::token($uid);
    }

    /** Crea el PIN o lo cambia (pide el actual). Devuelve el desbloqueo con el PIN nuevo. */
    public static function setPin(int $uid, string $pin, string $confirmation, string $current): string
    {
        self::validateNewPin($pin, $confirmation);
        if (PrivateChat::hasPin($uid)) {
            self::unlock($uid, $current, 'current_pin');
        }
        self::action($uid);
        PrivateChat::setPin($uid, $pin);
        return (string) self::token($uid);
    }

    /** Olvidé mi PIN: con la contraseña de la cuenta se vacían todos los chats privados y se crea un PIN nuevo. */
    public static function reset(array $user, string $password, string $pin, string $confirmation): string
    {
        self::validateNewPin($pin, $confirmation);
        SettingsService::confirmPassword($user, $password, 'password');
        $uid = (int) $user['id'];
        self::action($uid);
        self::emptyAll($uid);
        PrivateChat::setPin($uid, $pin);
        return (string) self::token($uid);
    }

    /**
     * Vacía los chats privados y los quita de la lista (como «eliminar chat», solo para esta persona). Siguen siendo
     * privados: si vuelven a escribir, el chat aparece entre los privados. Devuelve cuántos había.
     */
    public static function emptyAll(int $uid): int
    {
        $ids = Conversation::privateIds($uid);
        foreach ($ids as $id) {
            Conversation::clearFor($id, $uid, true);
        }
        return count($ids);
    }

    /** Desactiva los chats privados: vuelven a la bandeja y se borra el PIN. */
    public static function disable(int $uid): int
    {
        self::action($uid);
        $ids = Conversation::privateIds($uid);
        Conversation::setPrivate($ids, $uid, false);
        PrivateChat::deletePin($uid);
        return count($ids);
    }

    /** Antes de exportar con la contraseña (sin PIN) o con el desbloqueo. */
    public static function exportAllowed(array $user, bool $unlocked, string $password, string $field = 'password'): void
    {
        if (!$unlocked) {
            SettingsService::confirmPassword($user, $password, $field);
        }
        $key = 'user:' . (int) $user['id'];
        Guard::rateLimit('private_export', $key, 'Ya exportaste varias veces tus chats privados. Inténtalo de nuevo en {min} min.');
        RateLimit::hit('private_export', $key);
    }

    /**
     * Chats privados con sus mensajes para la app: los cifrados de extremo a extremo van tal cual (epoch y texto
     * cifrado) para que el teléfono los descifre; el servidor no puede leerlos.
     *
     * @return list<array{id:int, title:string, type:string, messages:list<array>}>
     */
    public static function export(int $uid): array
    {
        $out = [];
        foreach (self::collect($uid) as [$conversation, $messages]) {
            $out[] = [
                'id'       => (int) $conversation['id'],
                'title'    => self::title($conversation),
                'type'     => (string) $conversation['type'],
                'messages' => array_map(static fn (array $m): array => [
                    'id'          => (int) $m['id'],
                    'sender_id'   => $m['sender_id'] !== null ? (int) $m['sender_id'] : null,
                    'sender_name' => (int) $m['sender_id'] === $uid ? null : (string) ($m['sender_name'] ?? ''),
                    'mine'        => (int) $m['sender_id'] === $uid,
                    'text'        => self::line($m),
                    'media_url'   => self::mediaUrl($m),
                    'e2ee'        => self::sealed($m),
                    'created_at'  => Present::date($m['created_at']),
                ], $messages),
            ];
        }
        return $out;
    }

    /** La misma exportación en texto (la web): los mensajes cifrados solo se pueden exportar desde la app. */
    public static function exportText(int $uid): string
    {
        $lines = [t('Chats privados de TREVIX · exportados el {date}', ['date' => date('d/m/Y H:i')]), ''];
        foreach (self::collect($uid) as [$conversation, $messages]) {
            $lines[] = '== ' . self::title($conversation) . ' ==';
            foreach ($messages as $m) {
                $who = (int) $m['sender_id'] === $uid ? t('Tú') : ((string) ($m['sender_name'] ?? '') ?: t('Cuenta no disponible'));
                $text = self::sealed($m) !== null ? t('Mensaje cifrado (expórtalo desde la app TREVIX para leerlo)') : self::line($m);
                $url = self::mediaUrl($m);
                $lines[] = '[' . date('d/m/Y H:i', (int) strtotime((string) $m['created_at'])) . '] ' . $who . ': ' . $text . ($url !== null ? ' ' . $url : '');
            }
            $lines[] = '';
        }
        return implode("\r\n", $lines);
    }

    /** @return list<array{0:array, 1:list<array>}> */
    private static function collect(int $uid): array
    {
        $out = [];
        foreach (Conversation::privateIds($uid) as $id) {
            $conversation = Conversation::findFor($id, $uid);
            $messages = $conversation !== null ? Message::forExport($id, $uid, self::EXPORT_LIMIT) : [];
            if ($messages !== []) {
                $out[] = [$conversation, $messages];
            }
        }
        return $out;
    }

    private static function title(array $conversation): string
    {
        return $conversation['type'] === 'group'
            ? (string) $conversation['user']['display_name']
            : (string) (($conversation['nickname'] ?? null) ?: $conversation['user']['display_name']);
    }

    /** Texto completo del mensaje o, si no tiene, su resumen (Foto, Nota de voz, Ubicación…). */
    private static function line(array $m): string
    {
        $body = trim((string) ($m['body'] ?? ''));
        $plain = $m['deleted_at'] === null && empty($m['view_once']) && ($m['e2ee_epoch'] ?? null) === null && ($m['context'] ?? null) !== 'story_reaction';
        return $plain && $body !== '' ? $body : Message::summary($m);
    }

    private static function mediaUrl(array $m): ?string
    {
        if ($m['deleted_at'] !== null || !empty($m['view_once']) || ($m['e2ee_epoch'] ?? null) !== null) {
            return null;
        }
        $gif = (string) ($m['gif_url'] ?? '');
        return Present::file($m['media_path'] ?? null) ?? ($gif !== '' ? $gif : null);
    }

    /** @return array{epoch:int, ciphertext:string}|null */
    private static function sealed(array $m): ?array
    {
        if (($m['e2ee_epoch'] ?? null) === null || $m['deleted_at'] !== null || !empty($m['view_once'])) {
            return null;
        }
        return ['epoch' => (int) $m['e2ee_epoch'], 'ciphertext' => (string) $m['body']];
    }

    private static function validateNewPin(string $pin, string $confirmation): void
    {
        if (!self::validPin($pin)) {
            throw ActionError::field('pin', 'El PIN debe tener de 4 a 8 números.');
        }
        if (!hash_equals($pin, $confirmation)) {
            throw ActionError::field('pin_confirmation', 'Los PIN no coinciden.');
        }
    }

    private static function action(int $uid): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit('private_chats', $key, 'Hiciste demasiados cambios en tus chats privados. Inténtalo de nuevo en {min} min.');
        RateLimit::hit('private_chats', $key);
    }
}
