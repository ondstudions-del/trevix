<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Models\AuditLog;
use Trevix\Models\Report;
use Trevix\Models\User;

/** Medidas disponibles sobre un objetivo reportado y su aplicación (panel web y API de administración). */
final class ReportDecision
{
    /** Duraciones de suspensión que se ofrecen (días; 0 = sin fecha de fin). */
    public const DURATIONS = [1 => '1 día', 3 => '3 días', 7 => '7 días', 14 => '14 días', 30 => '30 días', 90 => '90 días', 365 => '1 año', 0 => 'Sin fecha de fin'];

    /** Medidas que quien revisa puede aplicar a este objetivo (clave => descripción). */
    public static function measures(array $staff, string $type, array $preview): array
    {
        $measures = [];
        $canContent = Moderation::canModerateContentOf($staff, $preview['author']);
        $alive = $preview['status'] === 'published';

        if ($type === 'post' && $canContent) {
            if ($alive) {
                $measures['hide'] = 'Ocultar la publicación';
            }
            $measures['delete'] = 'Eliminar la publicación';
        } elseif ($type === 'comment' && $canContent && $alive) {
            $measures['delete'] = 'Eliminar el comentario (y sus respuestas)';
        } elseif ($type === 'message' && $canContent && $alive) {
            $measures['delete'] = 'Eliminar el mensaje';
        } elseif ($type === 'story' && $canContent && $alive) {
            $measures['delete'] = 'Eliminar la historia';
        } elseif ($type === 'community' && Moderation::isAdmin($staff)) {
            if ($preview['status'] === 'active') {
                $measures['suspend_community'] = 'Suspender la comunidad';
            }
            $measures['delete_community'] = 'Eliminar la comunidad';
        }

        if (Moderation::canActOnUser($staff, $preview['author']) && $preview['author']['status'] !== 'deleted') {
            $measures['warn_user'] = $type === 'user' ? 'Advertir a la cuenta' : 'Advertir al autor (@' . $preview['author']['username'] . ')';
            $measures['suspend_user'] = $type === 'user' ? 'Suspender la cuenta' : 'Suspender al autor (@' . $preview['author']['username'] . ')';
        }
        return $measures;
    }

    /** Duraciones de suspensión permitidas a quien revisa. */
    public static function durations(array $staff): array
    {
        $max = Moderation::maxModeratorDays();
        return Moderation::isAdmin($staff)
            ? self::DURATIONS
            : array_filter(self::DURATIONS, static fn (int $days) => $days > 0 && $days <= $max, ARRAY_FILTER_USE_KEY);
    }

    /**
     * Resuelve los reportes de un objetivo aplicando una medida ('none' = resolver sin medida).
     * $days solo se usa al suspender una cuenta (0 = sin fecha de fin). Devuelve el mensaje para mostrar.
     *
     * @throws DomainException con un mensaje listo para mostrar
     */
    public static function resolve(array $staff, string $type, int $id, string $measure, int $days, ?string $note): string
    {
        if ($measure === 'none') {
            Moderation::closeReports($staff, $type, $id, 'resolved', $note);
            return 'Reportes marcados como resueltos.';
        }
        $preview = Report::preview($type, $id);
        if ($preview === null || !array_key_exists($measure, self::measures($staff, $type, $preview))) {
            throw new DomainException('Esa medida ya no está disponible para este objetivo.');
        }

        switch ($measure) {
            case 'hide':
                Moderation::hidePost($staff, $preview, $note);
                $message = 'Publicación ocultada y reportes resueltos.';
                break;
            case 'delete':
                match ($type) {
                    'post'    => Moderation::deletePost($staff, $preview, $note),
                    'comment' => Moderation::deleteComment($staff, $preview, $note),
                    'message' => Moderation::deleteMessage($staff, $id, $preview, $note),
                    'story'   => Moderation::deleteStory($staff, $preview, $note),
                };
                $message = 'Contenido eliminado y reportes resueltos.';
                break;
            case 'warn_user':
                $target = User::findForAdmin((int) $preview['author']['id']);
                if ($target === null) {
                    throw new DomainException('La cuenta ya no existe.');
                }
                Moderation::warnUser($staff, $target, (string) $note, $type, $id);
                $message = 'Advertimos a @' . $target['username'] . ' y los reportes quedaron resueltos.';
                break;
            case 'suspend_user':
                $target = User::findForAdmin((int) $preview['author']['id']);
                if ($target === null) {
                    throw new DomainException('La cuenta ya no existe.');
                }
                Moderation::suspendUser($staff, $target, $days > 0 ? $days : null, (string) $note);
                $message = 'Cuenta de @' . $target['username'] . ' suspendida y reportes resueltos.';
                break;
            case 'suspend_community':
                Moderation::suspendCommunity($staff, $preview['row'], (string) $note);
                $message = 'Comunidad suspendida y reportes resueltos.';
                break;
            default: // delete_community
                Moderation::deleteCommunity($staff, $preview['row'], (string) $note);
                $message = 'Comunidad eliminada y reportes resueltos.';
        }

        // La medida pudo cerrar los reportes de otro objetivo (p. ej. la cuenta del autor): se cierran también los de este.
        $closed = Report::close($type, $id, 'resolved', (int) $staff['id'], $note);
        if ($closed > 0) {
            AuditLog::record((int) $staff['id'], 'report.resolve', $type, $id, array_filter(['reports' => $closed, 'measure' => $measure, 'note' => $note]));
        }
        return $message;
    }
}
