<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Comment;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;

/** Comentar y borrar comentarios (compartido por la web y la API). */
final class CommentService
{
    /**
     * El comentario lleva texto, un GIF o sticker de GIPHY ($gifId + $gifKind), o ambos.
     *
     * @return array{id:int, post_id:int, parent_id:?int, body:string, gif:?array, post_owner_id:int}
     */
    public static function create(array $user, int $postId, string $body, int $parentParam = 0, string $gifId = '', string $gifKind = 'gif'): array
    {
        $uid = (int) $user['id'];
        $post = $postId > 0 ? Post::findVisible($postId, $uid) : null;
        if ($post === null) {
            throw new ActionError('Esta publicación ya no está disponible.', 404);
        }
        Guard::verifiedEmail($user);

        $rateKey = 'user:' . $uid;
        Guard::rateLimit('comment_create', $rateKey, 'Comentaste muchas veces seguidas. Espera unos minutos.');

        $body = Guard::cleanText($body);
        $max = (int) Config::get('app.limits.comment_body');
        if ($body === '' && trim($gifId) === '') {
            throw ActionError::field('body', 'Escribe tu comentario o elige un GIF.');
        }
        if (mb_strlen($body) > $max) {
            throw ActionError::field('body', 'El comentario no puede superar los ' . $max . ' caracteres.');
        }

        $parentId = null;
        $parent = null;
        if ($parentParam > 0) {
            $parent = Comment::find($parentParam);
            if ($parent === null || (int) $parent['post_id'] !== $postId) {
                throw new ActionError('El comentario al que respondes ya no existe.', 404);
            }
            // Un solo nivel de respuestas: responder a una respuesta cuelga del comentario principal.
            $parentId = $parent['parent_id'] !== null ? (int) $parent['parent_id'] : (int) $parent['id'];
        }

        $gif = Giphy::resolve($gifId, $gifKind);

        RateLimit::hit('comment_create', $rateKey);
        $id = Comment::create($postId, $uid, $parentId, $body, $gif);
        self::notify($uid, $post, $id, $parent, $body);
        return [
            'id' => $id, 'post_id' => $postId, 'parent_id' => $parentId, 'body' => $body,
            'gif' => $gif !== null ? Giphy::fromRow($gif) : null, 'post_owner_id' => (int) $post['user']['id'],
        ];
    }

    /** Puede borrar el autor del comentario o el autor de la publicación. Devuelve el id de la publicación. */
    public static function delete(int $uid, int $commentId): int
    {
        $comment = $commentId > 0 ? Comment::find($commentId) : null;
        $post = $comment !== null ? Post::findRaw((int) $comment['post_id']) : null;
        if ($comment === null || $post === null || ((int) $comment['user_id'] !== $uid && (int) $post['user_id'] !== $uid)) {
            throw new ActionError('No puedes eliminar este comentario.', 403);
        }
        Comment::delete($comment);
        return (int) $post['id'];
    }

    /**
     * Respuesta: avisa a quien escribió el comentario respondido. El autor de la publicación recibe
     * "comentó" salvo que ya lo avisara la respuesta. Los mencionados restantes reciben la mención.
     */
    private static function notify(int $uid, array $post, int $commentId, ?array $parent, string $body): void
    {
        $postId = (int) $post['id'];
        $notified = [];
        if ($parent !== null && Notification::notify((int) $parent['user_id'], $uid, 'reply', $postId, $commentId)) {
            $notified[] = (int) $parent['user_id'];
        }
        $ownerId = (int) $post['user']['id'];
        if (!in_array($ownerId, $notified, true) && ($parent === null || (int) $parent['user_id'] !== $ownerId)
            && Notification::notify($ownerId, $uid, 'comment', $postId, $commentId)) {
            $notified[] = $ownerId;
        }
        Notification::notifyMentions($uid, $body, $postId, $commentId, $notified);
    }
}
