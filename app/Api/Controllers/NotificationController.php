<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Follow;
use Trevix\Models\Notification;

/** Avisos de actividad. Las solicitudes de seguimiento van aparte, en /me/follow-requests. */
final class NotificationController extends ApiController
{
    /** GET /notifications?filter=all|mentions&before= */
    public function index(): never
    {
        $uid = $this->uid();
        $filter = Request::queryIn('filter', ['all', 'mentions'], 'all');
        $list = Notification::listFor(
            $uid,
            $filter === 'mentions' ? Notification::MENTION_TYPES : null,
            max(0, (int) Request::query('before')) ?: null,
            $this->limit('notifications_page', 30)
        );

        $followerIds = [];
        foreach ($list['items'] as $item) {
            if ($item['type'] === 'follow' && $item['actor'] !== null) {
                $followerIds[] = $item['actor']['id'];
            }
        }
        $relations = Follow::relationsFor($uid, $followerIds);
        foreach ($list['items'] as &$item) {
            if ($item['type'] === 'follow' && $item['actor'] !== null) {
                $item['actor']['relation'] = $relations[$item['actor']['id']];
            }
        }
        unset($item);

        Reply::ok(array_map([Present::class, 'notification'], $list['items']), [
            'next'   => $list['nextBefore'] !== null ? ['before' => $list['nextBefore']] : null,
            'counts' => Present::counts($this->user()),
        ]);
    }

    /** POST /notifications/read-all */
    public function readAll(): never
    {
        Reply::ok(['marked' => Notification::markAllRead($this->uid())]);
    }

    /** POST /notifications/{id}/read — devuelve a dónde lleva el aviso. */
    public function read(string $id): never
    {
        $uid = $this->uid();
        $notification = Notification::findFor($uid, (int) $id);
        if ($notification === null) {
            $this->notFound('Esa notificación ya no está disponible.');
        }
        Notification::markRead($uid, (int) $id);
        Reply::ok([
            'id'     => (int) $notification['id'],
            'target' => [
                'post_id'        => $notification['post_id'] !== null ? (int) $notification['post_id'] : null,
                'comment_id'     => $notification['comment_id'] !== null ? (int) $notification['comment_id'] : null,
                'community_slug' => $notification['community_slug'],
                'username'       => $notification['username'],
            ],
        ]);
    }
}
