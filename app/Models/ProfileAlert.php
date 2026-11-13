<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;
use Trevix\Services\PushNotifier;

/**
 * La campana del perfil: quien la activa recibe un aviso cuando esa cuenta publica, comparte una nota o sube una
 * historia, siempre que pueda ver lo publicado (privacidad, mejores amigos, suscriptores y bloqueos).
 */
final class ProfileAlert extends Model
{
    public const TYPES = ['new_post', 'new_note', 'new_story'];

    public static function isOn(int $userId, int $targetId): bool
    {
        return (bool) self::fetchValue('SELECT 1 FROM profile_alerts WHERE user_id = ? AND target_id = ?', [$userId, $targetId]);
    }

    public static function set(int $userId, int $targetId, bool $on): void
    {
        if ($on) {
            self::execute('INSERT IGNORE INTO profile_alerts (user_id, target_id) VALUES (?, ?)', [$userId, $targetId]);
        } else {
            self::execute('DELETE FROM profile_alerts WHERE user_id = ? AND target_id = ?', [$userId, $targetId]);
        }
    }

    /** Al bloquear: se apagan las campanas entre ambas cuentas. */
    public static function removeBetween(int $a, int $b): void
    {
        self::execute('DELETE FROM profile_alerts WHERE (user_id = ? AND target_id = ?) OR (user_id = ? AND target_id = ?)', [$a, $b, $b, $a]);
    }

    /**
     * Avisa a quienes activaron la campana de $authorId. $id es la publicación, la nota o la historia; cada persona
     * solo recibe el aviso si puede verla. Un aviso nuevo de nota o historia reemplaza el anterior sin leer de la
     * misma cuenta, para no llenar la bandeja con cada historia.
     */
    public static function fire(string $type, int $authorId, int $id): void
    {
        if (!in_array($type, self::TYPES, true) || $id < 1) {
            return;
        }
        $limit = max(1, (int) Config::get('app.limits.profile_alerts_fanout', 2000));
        $ids = array_map('intval', array_column(self::fetchAll(
            "SELECT pa.user_id FROM profile_alerts pa JOIN users u ON u.id = pa.user_id
             WHERE pa.target_id = ? AND u.status = 'active'
             ORDER BY pa.created_at LIMIT $limit",
            [$authorId]
        ), 'user_id'));
        foreach ($ids as $userId) {
            $visible = match ($type) {
                'new_post'  => Post::findVisible($id, $userId) !== null,
                'new_note'  => Note::findVisible($id, $userId) !== null,
                'new_story' => Story::findVisible($id, $userId) !== null,
            };
            if (!$visible) {
                continue;
            }
            if ($type !== 'new_post') {
                self::execute('DELETE FROM notifications WHERE user_id = ? AND actor_id = ? AND type = ? AND read_at IS NULL', [$userId, $authorId, $type]);
            }
            self::execute(
                'INSERT INTO notifications (user_id, actor_id, type, post_id, ref_id) VALUES (?, ?, ?, ?, ?)',
                [$userId, $authorId, $type, $type === 'new_post' ? $id : null, $type === 'new_post' ? null : $id]
            );
            PushNotifier::user($userId);
        }
    }
}
