<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\Block;
use Trevix\Models\Follow;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/** Seguir, responder solicitudes y bloquear (compartido por la web y la API). */
final class RelationshipService
{
    public const FOLLOW_ACTIONS = ['follow', 'unfollow', 'cancel', 'accept', 'reject', 'remove'];
    public const BLOCK_ACTIONS = ['block', 'unblock'];

    /**
     * @param string $action follow | unfollow | cancel | accept | reject | remove
     * @return array{target: array, state: ?string, message: string, followers_count: int}
     */
    public static function follow(int $uid, int $targetId, string $action): array
    {
        if (!in_array($action, self::FOLLOW_ACTIONS, true)) {
            throw new ActionError('Acción no válida.', 400);
        }
        $target = self::target($uid, $targetId, 'follow', true);
        $tid = (int) $target['id'];
        $handle = '@' . $target['username'];
        if (in_array($action, ['follow', 'accept'], true) && $target['status'] !== 'active') {
            throw new ActionError('Esta cuenta no está disponible.', 404);
        }

        $state = null;
        switch ($action) {
            case 'follow':
                $state = Follow::follow($uid, $target);
                $message = $state === 'requested' ? t('Enviamos tu solicitud a {handle}.', ['handle' => $handle]) : t('Ahora sigues a {handle}.', ['handle' => $handle]);
                break;
            case 'unfollow':
            case 'cancel':
                Follow::unfollow($uid, $tid);
                $state = 'none';
                $message = $action === 'cancel' ? t('Cancelaste la solicitud a {handle}.', ['handle' => $handle]) : t('Dejaste de seguir a {handle}.', ['handle' => $handle]);
                break;
            case 'accept':
                if (!Follow::accept($uid, $tid)) {
                    throw new ActionError('Esa solicitud ya no está pendiente.', 409);
                }
                $message = t('{handle} ahora te sigue.', ['handle' => $handle]);
                break;
            case 'reject':
                Follow::reject($uid, $tid);
                $message = t('Rechazaste la solicitud de {handle}.', ['handle' => $handle]);
                break;
            default: // remove
                Follow::removeFollower($uid, $tid);
                $message = t('{handle} ya no te sigue.', ['handle' => $handle]);
        }

        return ['target' => $target, 'state' => $state, 'message' => $message, 'followers_count' => User::followersCount($tid)];
    }

    /**
     * @param string $action block | unblock
     * @return array{target: array, message: string}
     */
    public static function block(int $uid, int $targetId, string $action): array
    {
        if (!in_array($action, self::BLOCK_ACTIONS, true)) {
            throw new ActionError('Acción no válida.', 400);
        }
        $target = self::target($uid, $targetId, 'block', false);
        $handle = '@' . $target['username'];
        if ($action === 'block') {
            Block::block($uid, (int) $target['id']);
            return ['target' => $target, 'message' => t('Bloqueaste a {handle}. No podrán ver el perfil ni las publicaciones del otro.', ['handle' => $handle])];
        }
        Block::unblock($uid, (int) $target['id']);
        return ['target' => $target, 'message' => t('Desbloqueaste a {handle}.', ['handle' => $handle])];
    }

    /**
     * Cuenta sobre la que se actúa: existe, no es la propia, respeta el límite de acciones y,
     * para seguir, no hay un bloqueo entre ambas.
     */
    private static function target(int $uid, int $id, string $rateAction, bool $rejectBlocked): array
    {
        $rateKey = 'user:' . $uid;
        Guard::rateLimit($rateAction, $rateKey, 'Vas demasiado rápido. Espera unos minutos.');

        $target = $id > 0 ? User::findForRelation($id) : null;
        if ($target === null || ($rejectBlocked && User::blockedBetween($uid, $id))) {
            throw new ActionError('Esta cuenta no está disponible.', 404);
        }
        if ($id === $uid) {
            throw new ActionError('No puedes hacer esto con tu propia cuenta.');
        }

        RateLimit::hit($rateAction, $rateKey);
        return $target;
    }
}
