<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Comment;
use Trevix\Models\Community;
use Trevix\Models\Conversation;
use Trevix\Models\Message;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\Report;
use Trevix\Models\Story;
use Trevix\Models\User;

/** Reportar contenido o cuentas: solo lo que uno puede ver y que no es propio (web y API). */
final class ReportService
{
    /**
     * Envía o reabre un reporte.
     *
     * @return array{status: string, message: string, target: array{label:string, url:string}}
     */
    public static function submit(int $uid, string $type, int $id, string $reason, string $details): array
    {
        $target = isset(Report::TYPES[$type]) ? self::target($type, $id, $uid) : null;
        if ($target === null) {
            throw new ActionError('No encontramos ese contenido o no puedes reportarlo.', 404);
        }

        $key = (string) $uid;
        Guard::rateLimit('report', $key, 'Enviaste muchos reportes seguidos. Inténtalo de nuevo en {min} min.');

        $details = Guard::cleanText($details);
        $max = (int) Config::get('app.limits.report_details', 1000);
        $errors = [];
        if (!isset(Report::REASONS[$reason])) {
            $errors['reason'] = 'Elige el motivo del reporte.';
        }
        if (mb_strlen($details) > $max) {
            $errors['details'] = 'Los detalles pueden tener como máximo ' . $max . ' caracteres.';
        } elseif ($reason === 'other' && mb_strlen($details) < 5) {
            $errors['details'] = 'Cuéntanos brevemente qué ocurre.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $status = Report::create($uid, $type, $id, $reason, $details !== '' ? $details : null);
        if ($status !== 'exists') {
            RateLimit::hit('report', $key);
        }
        $message = $status === 'exists'
            ? 'Ya habías reportado esto. El equipo de moderación lo está revisando.'
            : 'Gracias por avisarnos. El equipo de moderación revisará tu reporte.';
        return ['status' => $status, 'message' => $message, 'target' => $target];
    }

    /**
     * Objetivo que $uid puede reportar: visible para él y de otra persona.
     * @return array{label:string, url:string}|null
     */
    public static function target(string $type, int $id, int $uid): ?array
    {
        if ($id < 1) {
            return null;
        }
        switch ($type) {
            case 'post':
                $post = Post::findVisible($id, $uid);
                if ($post === null || (int) $post['user_id'] === $uid) {
                    return null;
                }
                return ['label' => 'la publicación de @' . $post['user']['username'], 'url' => url('post.php', ['id' => $id])];

            case 'comment':
                $comment = Comment::find($id);
                if ($comment === null || (int) $comment['user_id'] === $uid || Post::findVisible((int) $comment['post_id'], $uid) === null) {
                    return null;
                }
                $author = User::findForRelation((int) $comment['user_id']);
                if ($author === null || $author['status'] !== 'active' || User::blockedBetween($uid, (int) $author['id'])) {
                    return null;
                }
                return [
                    'label' => 'el comentario de @' . $author['username'],
                    'url'   => url('post.php', ['id' => (int) $comment['post_id']]) . '#comentario-' . $id,
                ];

            case 'user':
                $user = User::findForRelation($id);
                if ($user === null || $user['status'] !== 'active' || $id === $uid) {
                    return null;
                }
                return ['label' => 'la cuenta @' . $user['username'], 'url' => url('profile.php', ['u' => $user['username']])];

            case 'community':
                $community = Community::find($id, $uid);
                if ($community === null || $community['owner_id'] === $uid) {
                    return null;
                }
                return ['label' => 'la comunidad «' . $community['name'] . '»', 'url' => community_url($community)];

            case 'message':
                $message = Message::find($id);
                if ($message === null || $message['deleted_at'] !== null || $message['sender_id'] === null
                    || (int) $message['sender_id'] === $uid
                    || Conversation::findFor((int) $message['conversation_id'], $uid) === null) {
                    return null;
                }
                $sender = User::findForRelation((int) $message['sender_id']);
                return [
                    'label' => 'un mensaje de @' . ($sender['username'] ?? 'usuario'),
                    'url'   => url('messages.php', ['c' => (int) $message['conversation_id']]) . '#mensaje-' . $id,
                ];

            case 'story':
                $story = Story::findVisible($id, $uid);
                if ($story === null || (int) $story['user_id'] === $uid) {
                    return null;
                }
                return ['label' => 'la historia de @' . $story['username'], 'url' => url('stories.php', ['u' => $story['username']])];
        }
        return null;
    }
}
