<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\Config;
use Trevix\Models\ApiToken;
use Trevix\Models\AuditLog;
use Trevix\Models\Comment;
use Trevix\Models\Community;
use Trevix\Models\Message;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\Report;
use Trevix\Models\Song;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Models\Warning;

/**
 * Acciones de moderación y administración. Cada método comprueba los permisos de quien actúa, aplica el
 * cambio, cierra los reportes pendientes del objetivo y lo anota en la auditoría.
 *
 * Reglas:
 *  - Nadie actúa sobre sí mismo ni sobre su propio contenido desde el panel.
 *  - Sobre una cuenta solo actúa quien tiene un rango estrictamente mayor.
 *  - Los moderadores moderan contenido de usuarios y suspenden cuentas de usuario como máximo N días.
 *  - Los administradores además cambian roles y verificación, suspenden sin fecha y gestionan comunidades.
 *
 * Los errores se lanzan como DomainException con un mensaje listo para mostrar.
 */
final class Moderation
{
    private const RANK = ['user' => 1, 'moderator' => 2, 'admin' => 3];

    public static function rank(?string $role): int
    {
        return self::RANK[$role ?? 'user'] ?? 1;
    }

    public static function isAdmin(array $actor): bool
    {
        return ($actor['role'] ?? '') === 'admin';
    }

    /** $actor puede actuar sobre la cuenta $target. */
    public static function canActOnUser(array $actor, array $target): bool
    {
        return (int) $actor['id'] !== (int) $target['id'] && self::rank($actor['role'] ?? null) > self::rank($target['role'] ?? null);
    }

    /** $actor puede moderar contenido de $author (los administradores, el de cualquiera salvo el propio). */
    public static function canModerateContentOf(array $actor, array $author): bool
    {
        if ((int) $actor['id'] === (int) $author['id']) {
            return false;
        }
        return self::isAdmin($actor) || self::rank($actor['role'] ?? null) > self::rank($author['role'] ?? null);
    }

    public static function maxModeratorDays(): int
    {
        return (int) Config::get('app.limits.moderator_suspension_days', 30);
    }

    // -------------------------------------------------------------------------
    // Contenido
    // -------------------------------------------------------------------------

    /** @param array $target vista previa de Report::preview('post', id) */
    public static function hidePost(array $actor, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        if (!Post::setModerationStatus($target['row'], 'hidden')) {
            throw new DomainException('La publicación ya no está publicada.');
        }
        self::finish($actor, 'post.hide', 'post', (int) $target['row']['id'], $note, ['author' => $target['author']['username']]);
    }

    public static function restorePost(array $actor, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        if (!Post::setModerationStatus($target['row'], 'published')) {
            throw new DomainException('La publicación no estaba oculta.');
        }
        AuditLog::record((int) $actor['id'], 'post.restore', 'post', (int) $target['row']['id'], array_filter([
            'author' => $target['author']['username'], 'note' => $note,
        ]));
    }

    /**
     * Destaca una publicación pública (arriba del inicio y en Destacados de Explorar) o la quita de destacadas.
     * Es una decisión editorial: solo administradores, también sobre publicaciones propias.
     */
    public static function featurePost(array $actor, int $postId, bool $feature): void
    {
        self::requireAdmin($actor);
        $raw = Post::findRaw($postId);
        if ($raw === null || $raw['status'] !== 'published') {
            throw new DomainException('La publicación ya no está publicada.');
        }
        if ($feature) {
            $community = !empty($raw['community_id']) ? Community::findAny((int) $raw['community_id']) : null;
            if ($raw['visibility'] !== 'public' || ($community !== null && $community['visibility'] !== 'public')) {
                throw new DomainException('Solo se pueden destacar publicaciones públicas.');
            }
        }
        if (!Post::setFeatured($postId, $feature ? (int) $actor['id'] : null)) {
            throw new DomainException($feature ? 'La publicación ya estaba destacada.' : 'La publicación no estaba destacada.');
        }
        if ($feature) {
            Notification::notify((int) $raw['user_id'], (int) $actor['id'], 'featured', $postId);
        }
        AuditLog::record((int) $actor['id'], $feature ? 'post.feature' : 'post.unfeature', 'post', $postId, []);
    }

    public static function deletePost(array $actor, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        Post::delete($target['row']);
        self::finish($actor, 'post.delete', 'post', (int) $target['row']['id'], $note, [
            'author' => $target['author']['username'], 'excerpt' => self::excerpt($target['excerpt']),
        ]);
    }

    public static function deleteComment(array $actor, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        if ($target['status'] !== 'published' || Comment::find((int) $target['row']['id']) === null) {
            throw new DomainException('El comentario ya no existe.');
        }
        Comment::delete($target['row']);
        self::finish($actor, 'comment.delete', 'comment', (int) $target['row']['id'], $note, [
            'author' => $target['author']['username'], 'post_id' => $target['row']['post_id'], 'excerpt' => self::excerpt($target['excerpt']),
        ]);
    }

    /** @param int $messageId  $target = Report::preview('message', id) */
    public static function deleteMessage(array $actor, int $messageId, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        if (!Message::deleteByModerator($messageId)) {
            throw new DomainException('El mensaje ya estaba eliminado.');
        }
        self::finish($actor, 'message.delete', 'message', $messageId, $note, ['author' => $target['author']['username']]);
    }

    public static function deleteStory(array $actor, array $target, ?string $note): void
    {
        self::guardContent($actor, $target);
        if ($target['status'] !== 'published') {
            throw new DomainException('La historia ya caducó.');
        }
        Story::delete($target['row']);
        self::finish($actor, 'story.delete', 'story', (int) $target['row']['id'], $note, ['author' => $target['author']['username']]);
    }

    // -------------------------------------------------------------------------
    // Música
    // -------------------------------------------------------------------------

    /** @param array $song Song::findRaw() */
    public static function approveSong(array $actor, array $song, ?string $note): void
    {
        self::guardSong($actor, $song);
        if (!Song::transition((int) $song['id'], ['pending'], 'published', (int) $actor['id'], $note)) {
            throw new DomainException('Esta canción ya no está en revisión.');
        }
        self::notifyArtist($song, 'song_approved', (int) $song['id']);
        self::recordSong($actor, 'song.approve', $song, $note);
    }

    public static function rejectSong(array $actor, array $song, string $reason): void
    {
        self::guardSong($actor, $song);
        self::requireReason($reason);
        if (!Song::transition((int) $song['id'], ['pending'], 'rejected', (int) $actor['id'], $reason)) {
            throw new DomainException('Esta canción ya no está en revisión.');
        }
        self::notifyArtist($song, 'song_rejected', (int) $song['id']);
        self::recordSong($actor, 'song.reject', $song, $reason);
    }

    /** Retira de la biblioteca una canción publicada (o retirada por el artista): deja de sonar en todas partes. */
    public static function removeSong(array $actor, array $song, string $reason): void
    {
        self::guardSong($actor, $song);
        self::requireReason($reason);
        if (!Song::transition((int) $song['id'], ['published', 'withdrawn'], 'removed', (int) $actor['id'], $reason)) {
            throw new DomainException('Esta canción no está publicada.');
        }
        self::notifyArtist($song, 'song_removed', (int) $song['id']);
        self::recordSong($actor, 'song.remove', $song, $reason);
    }

    public static function restoreSong(array $actor, array $song, ?string $note): void
    {
        self::guardSong($actor, $song);
        if (!Song::transition((int) $song['id'], ['removed'], 'published', (int) $actor['id'], $note)) {
            throw new DomainException('Esta canción no estaba retirada por moderación.');
        }
        self::notifyArtist($song, 'song_approved', (int) $song['id']);
        self::recordSong($actor, 'song.restore', $song, $note);
    }

    private static function guardSong(array $actor, array $song): void
    {
        if (!self::canModerateContentOf($actor, ['id' => (int) $song['artist_id'], 'role' => $song['artist_role'] ?? 'user'])) {
            throw new DomainException('No puedes revisar esta canción.');
        }
    }

    /** Las canciones de catálogos externos no tienen artista en TREVIX a quien avisar. */
    private static function notifyArtist(array $song, string $type): void
    {
        if (!empty($song['artist_id'])) {
            Notification::notifySong((int) $song['artist_id'], $type, (int) $song['id']);
        }
    }

    private static function recordSong(array $actor, string $action, array $song, ?string $note): void
    {
        AuditLog::record((int) $actor['id'], $action, 'song', (int) $song['id'], array_filter([
            'title' => $song['title'], 'artist' => $song['username'] ?? null, 'note' => $note,
        ]));
    }

    // -------------------------------------------------------------------------
    // Cuentas
    // -------------------------------------------------------------------------

    /** @param ?int $days null = sin fecha de fin (solo administradores) */
    public static function suspendUser(array $actor, array $target, ?int $days, string $reason): void
    {
        self::guardUser($actor, $target);
        if (!self::isAdmin($actor) && ($days === null || $days > self::maxModeratorDays())) {
            throw new DomainException('Los moderadores pueden suspender como máximo ' . self::maxModeratorDays() . ' días.');
        }
        if ($days !== null && ($days < 1 || $days > 3650)) {
            throw new DomainException('Elige una duración válida.');
        }
        self::requireReason($reason);
        $until = $days !== null ? date('Y-m-d H:i:s', time() + $days * 86400) : null;
        if (!User::suspend((int) $target['id'], $until, $reason)) {
            throw new DomainException('No se pudo suspender esta cuenta.');
        }
        ApiToken::revokeAllFor((int) $target['id']);
        self::finish($actor, 'user.suspend', 'user', (int) $target['id'], $reason, [
            'username' => $target['username'], 'days' => $days, 'until' => $until,
        ]);
    }

    public static function unsuspendUser(array $actor, array $target, ?string $note): void
    {
        self::guardUser($actor, $target);
        if (!User::unsuspend((int) $target['id'])) {
            throw new DomainException('La cuenta no estaba suspendida.');
        }
        AuditLog::record((int) $actor['id'], 'user.unsuspend', 'user', (int) $target['id'], array_filter([
            'username' => $target['username'], 'note' => $note,
        ]));
    }

    /**
     * Advierte a una cuenta: la persona recibe un aviso con el motivo y, durante los próximos días, no puede pedir
     * el verificado. $targetType / $targetId: el contenido que la motivó, si lo hay.
     */
    public static function warnUser(array $actor, array $target, string $reason, ?string $targetType = null, ?int $targetId = null): int
    {
        self::guardUser($actor, $target);
        self::requireReason($reason);
        if ($target['status'] === 'deleted') {
            throw new DomainException('Esta cuenta ya no existe.');
        }
        $id = Warning::create((int) $target['id'], (int) $actor['id'], $reason, $targetType, $targetId);
        Notification::notifySystem((int) $target['id'], 'warning', $id);
        AuditLog::record((int) $actor['id'], 'user.warn', 'user', (int) $target['id'], array_filter([
            'username' => $target['username'], 'note' => $reason, 'about' => $targetType !== null && $targetType !== 'user' ? $targetType . ' #' . $targetId : null,
        ]));
        return $id;
    }

    /** Retira una advertencia (deja de contar para el verificado); queda en el historial como retirada. */
    public static function revokeWarning(array $actor, int $warningId, ?string $note): void
    {
        $warning = Warning::find($warningId) ?? throw new DomainException('Esta advertencia no existe.');
        $target = User::findForAdmin((int) $warning['user_id']) ?? throw new DomainException('Esta cuenta ya no existe.');
        self::guardUser($actor, $target);
        if (!Warning::revoke($warningId, (int) $actor['id'])) {
            throw new DomainException('Esta advertencia ya estaba retirada.');
        }
        AuditLog::record((int) $actor['id'], 'user.warning_revoke', 'user', (int) $target['id'], array_filter([
            'username' => $target['username'], 'warning' => $warningId, 'note' => $note,
        ]));
    }

    public static function setRole(array $actor, array $target, string $role): void
    {
        self::requireAdmin($actor);
        if ((int) $actor['id'] === (int) $target['id']) {
            throw new DomainException('No puedes cambiar tu propio rol.');
        }
        if (!isset(self::RANK[$role])) {
            throw new DomainException('Elige un rol válido.');
        }
        if ($target['role'] === $role) {
            throw new DomainException('La cuenta ya tiene ese rol.');
        }
        if ($target['role'] === 'admin' && User::activeAdminCount() <= 1) {
            throw new DomainException('Debe quedar al menos un administrador activo.');
        }
        User::setRole((int) $target['id'], $role);
        AuditLog::record((int) $actor['id'], 'user.role', 'user', (int) $target['id'], [
            'username' => $target['username'], 'from' => $target['role'], 'to' => $role,
        ]);
    }

    public static function setVerified(array $actor, array $target, bool $verified): void
    {
        self::requireAdmin($actor);
        if ((bool) $target['is_verified'] === $verified) {
            throw new DomainException($verified ? 'La cuenta ya está verificada.' : 'La cuenta no está verificada.');
        }
        User::setVerified((int) $target['id'], $verified);
        AuditLog::record((int) $actor['id'], $verified ? 'user.verify' : 'user.unverify', 'user', (int) $target['id'], [
            'username' => $target['username'],
        ]);
    }

    // -------------------------------------------------------------------------
    // Comunidades (solo administradores)
    // -------------------------------------------------------------------------

    public static function suspendCommunity(array $actor, array $community, string $reason): void
    {
        self::requireAdmin($actor);
        self::requireReason($reason);
        if (!Community::setModerationStatus((int) $community['id'], 'suspended')) {
            throw new DomainException('La comunidad ya estaba suspendida.');
        }
        self::finish($actor, 'community.suspend', 'community', (int) $community['id'], $reason, ['name' => $community['name']]);
    }

    public static function restoreCommunity(array $actor, array $community, ?string $note): void
    {
        self::requireAdmin($actor);
        if (!Community::setModerationStatus((int) $community['id'], 'active')) {
            throw new DomainException('La comunidad no estaba suspendida.');
        }
        AuditLog::record((int) $actor['id'], 'community.restore', 'community', (int) $community['id'], array_filter([
            'name' => $community['name'], 'note' => $note,
        ]));
    }

    public static function deleteCommunity(array $actor, array $community, string $reason): void
    {
        self::requireAdmin($actor);
        self::requireReason($reason);
        Community::delete($community);
        self::finish($actor, 'community.delete', 'community', (int) $community['id'], $reason, [
            'name' => $community['name'], 'slug' => $community['slug'], 'members' => (int) $community['members_count'],
        ]);
    }

    // -------------------------------------------------------------------------
    // Reportes
    // -------------------------------------------------------------------------

    public static function takeReports(array $actor, string $type, int $targetId): void
    {
        if (Report::markReviewing($type, $targetId, (int) $actor['id']) === 0) {
            throw new DomainException('No hay reportes nuevos para tomar.');
        }
        AuditLog::record((int) $actor['id'], 'report.reviewing', $type, $targetId);
    }

    /** Cierra los reportes del objetivo sin aplicar ninguna medida (descartados o resueltos). */
    public static function closeReports(array $actor, string $type, int $targetId, string $status, ?string $note): void
    {
        $closed = Report::close($type, $targetId, $status, (int) $actor['id'], $note);
        if ($closed === 0) {
            throw new DomainException('Estos reportes ya estaban cerrados.');
        }
        AuditLog::record((int) $actor['id'], $status === 'dismissed' ? 'report.dismiss' : 'report.resolve', $type, $targetId, array_filter([
            'reports' => $closed, 'note' => $note,
        ]));
    }

    // -------------------------------------------------------------------------

    private static function guardContent(array $actor, array $target): void
    {
        if (!self::canModerateContentOf($actor, $target['author'])) {
            throw new DomainException('No tienes permiso para moderar este contenido.');
        }
    }

    private static function guardUser(array $actor, array $target): void
    {
        if (!self::canActOnUser($actor, $target)) {
            throw new DomainException('No tienes permiso para actuar sobre esta cuenta.');
        }
    }

    private static function requireAdmin(array $actor): void
    {
        if (!self::isAdmin($actor)) {
            throw new DomainException('Esta acción es exclusiva de los administradores.');
        }
    }

    private static function requireReason(string $reason): void
    {
        if (mb_strlen(trim($reason)) < 5) {
            throw new DomainException('Escribe el motivo (al menos 5 caracteres).');
        }
    }

    /** Cierra como resueltos los reportes pendientes del objetivo y anota la acción. */
    private static function finish(array $actor, string $action, string $type, int $targetId, ?string $note, array $details): void
    {
        $closed = Report::close($type, $targetId, 'resolved', (int) $actor['id'], $note ?: (AuditLog::ACTIONS[$action] ?? null));
        AuditLog::record((int) $actor['id'], $action, $type, $targetId, array_filter($details + [
            'note' => $note, 'reports' => $closed,
        ], static fn ($v) => $v !== null && $v !== '' && $v !== 0));
    }

    private static function excerpt(string $text): string
    {
        return mb_strimwidth(trim($text), 0, 120, '…');
    }
}
