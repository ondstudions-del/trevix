<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Models\Conversation;
use Trevix\Models\Story;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;
use Trevix\Services\StoryService;

/** Historias de 24 horas: barra con sus elementos, publicar, marcar vistas, quién las vio, borrar y responder. */
final class StoryController extends ApiController
{
    /** GET /stories — grupos de la barra (las propias primero) con todos sus elementos. */
    public function index(): never
    {
        $uid = $this->uid();
        Story::purgeExpired(50);
        $ids = array_map(static fn (array $g) => (int) $g['user']['id'], Story::tray($uid));
        $groups = Story::groupsFor($ids, $uid);
        Reply::ok(array_map(function (array $group) use ($uid): array {
            $group['replyBlocked'] = (int) $group['user']['id'] === $uid ? null : Conversation::cannotMessage(
                $uid,
                $group['user'],
                Conversation::findDirectId($uid, (int) $group['user']['id'])
            );
            $out = Present::storyGroup($group);
            $out['has_unseen'] = !$out['own'] && in_array(false, array_column($out['items'], 'seen'), true);
            return $out;
        }, $groups));
    }

    /**
     * POST /stories — de texto {type: "text", text, background} o multimedia
     * (multipart: type=media, caption?, archivo en «media»; imagen o video corto). Ambas admiten
     * song_id y song_start (inicio del fragmento) para sumar una canción de la biblioteca.
     */
    public function create(): never
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === [] && !str_contains(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'json')) {
            throw new ActionError('El archivo supera el tamaño que acepta el servidor.', 413);
        }
        $user = $this->user();
        $id = StoryService::create(
            $user,
            Input::str('type') === 'text' ? 'text' : 'media',
            Input::str('text', false),
            Input::str('caption', false),
            Input::str('background'),
            MediaUpload::collect('media'),
            Input::int('song_id'),
            Input::int('song_start')
        );
        $this->created(['id' => $id, 'message' => 'Tu historia se publicó. Estará visible durante 24 horas.']);
    }

    /** POST /stories/{id}/view */
    public function view(string $id): never
    {
        $uid = $this->uid();
        $story = Story::findVisible((int) $id, $uid);
        if ($story === null) {
            $this->notFound('Esta historia ya no está disponible.');
        }
        Reply::ok(['new' => Story::markViewed($story, $uid)]);
    }

    /** GET /stories/{id}/viewers — solo de las historias propias. */
    public function viewers(string $id): never
    {
        $story = Story::findOwn((int) $id, $this->uid());
        if ($story === null) {
            $this->notFound('Solo puedes ver quién vio tus propias historias.');
        }
        Reply::ok(
            array_map(static fn (array $v) => Present::user($v) + ['viewed_at' => Present::date($v['viewed_at'])], Story::viewers((int) $story['id'])),
            ['count' => (int) $story['views_count']]
        );
    }

    /** DELETE /stories/{id} */
    public function destroy(string $id): never
    {
        Reply::ok(['message' => 'Eliminaste la historia.', 'remaining' => StoryService::delete($this->uid(), (int) $id)]);
    }

    /** POST /stories/{id}/reply {body} — envía un mensaje privado al autor. */
    public function reply(string $id): never
    {
        $result = MessageService::replyToStory($this->user(), (int) $id, Input::str('body', false));
        $this->created([
            'conversation_id' => $result['conversation_id'],
            'message_id'      => $result['message_id'],
            'message'         => 'Enviaste tu respuesta a @' . $result['story']['username'] . '.',
        ]);
    }
}
