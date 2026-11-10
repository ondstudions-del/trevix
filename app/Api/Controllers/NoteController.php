<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\Note;
use Trevix\Services\MessageService;
use Trevix\Services\NoteService;

/** Notas de 6 horas (nube sobre el avatar), responderlas por mensaje privado y la lista de mejores amigos. */
final class NoteController extends ApiController
{
    /** GET /notes — la propia (si hay) y las visibles de las cuentas que sigues; meta con las opciones. */
    public function index(): never
    {
        $uid = $this->uid();
        Note::purgeExpired();
        Reply::ok(array_map([Present::class, 'note'], Note::tray($uid)), self::options($uid));
    }

    /** POST /notes {body?, audience: followers|friends|close_friends, sticker_id?, song_id?, song_start?} */
    public function create(): never
    {
        $note = NoteService::publish(
            $this->user(),
            Input::str('body', false),
            Input::str('audience') ?: 'followers',
            Input::str('sticker_id'),
            Input::int('song_id'),
            Input::int('song_start')
        );
        $this->created(['note' => Present::note($note), 'message' => 'Publicaste tu nota. Se verá durante 6 horas.']);
    }

    /** POST /notes/{id}/view — quien abre la nota de otra persona cuenta como una vista. */
    public function view(string $id): never
    {
        $uid = $this->uid();
        $note = Note::findVisible((int) $id, $uid);
        if ($note === null) {
            throw new ActionError('Esta nota ya no está disponible.', 404);
        }
        Note::view($note, $uid);
        Reply::ok(Present::note($note));
    }

    /** POST /notes/{id}/like · DELETE /notes/{id}/like */
    public function like(string $id): never
    {
        Reply::ok(Present::note(NoteService::like($this->uid(), (int) $id, true)));
    }

    public function unlike(string $id): never
    {
        Reply::ok(Present::note(NoteService::like($this->uid(), (int) $id, false)));
    }

    /** GET /notes/{id}/activity — solo la propia: quién la vio (y si es una amistad) y quién le dio me gusta. */
    public function activity(string $id): never
    {
        $uid = $this->uid();
        $note = Note::findVisible((int) $id, $uid);
        if ($note === null || (int) $note['user_id'] !== $uid) {
            throw new ActionError('Esta nota ya no está disponible.', 404);
        }
        Reply::ok(array_map(static fn (array $u): array => Present::user($u) + [
            'liked'     => (bool) $u['liked'],
            'friend'    => (bool) $u['friend'],
            'viewed_at' => Present::date($u['viewed_at']),
        ], Note::viewers($note)), [
            'views'        => $note['views'],
            'friend_views' => $note['friend_views'],
            'likes'        => $note['likes'],
        ]);
    }

    /** DELETE /notes — borra la nota propia. */
    public function destroy(): never
    {
        NoteService::remove($this->uid());
        Reply::ok(['message' => 'Eliminaste tu nota.']);
    }

    /** POST /notes/{id}/reply {body} — mensaje privado al autor con el texto de la nota. */
    public function reply(string $id): never
    {
        $result = MessageService::replyToNote($this->user(), (int) $id, Input::str('body', false));
        $this->created([
            'conversation_id' => $result['conversation_id'],
            'message_id'      => $result['message_id'],
            'message'         => 'Enviaste tu respuesta a @' . $result['note']['username'] . '.',
        ]);
    }

    /** GET /me/close-friends — tu lista de mejores amigos. */
    public function closeFriends(): never
    {
        $uid = $this->uid();
        Reply::ok(array_map([Present::class, 'user'], Note::closeFriends($uid)), ['count' => Note::closeFriendsCount($uid)]);
    }

    /** GET /me/close-friends/candidates?q= — tus seguidores y las cuentas que sigues, con «selected». */
    public function candidates(): never
    {
        $query = trim(ltrim(trim(Request::query('q')), '@'));
        Reply::ok(array_map(
            static fn (array $u): array => Present::user($u) + ['selected' => (bool) $u['selected']],
            Note::candidates($this->uid(), mb_substr($query, 0, 40))
        ));
    }

    /** POST /me/close-friends/{id} · DELETE /me/close-friends/{id} */
    public function addCloseFriend(string $id): never
    {
        $uid = $this->uid();
        NoteService::addCloseFriend($uid, (int) $id);
        Reply::ok(['selected' => true, 'count' => Note::closeFriendsCount($uid)]);
    }

    public function removeCloseFriend(string $id): never
    {
        $uid = $this->uid();
        NoteService::removeCloseFriend($uid, (int) $id);
        Reply::ok(['selected' => false, 'count' => Note::closeFriendsCount($uid)]);
    }

    private static function options(int $uid): array
    {
        return [
            'max_length'          => (int) Config::get('app.notes.max_length', 60),
            'ttl_seconds'         => (int) Config::get('app.notes.ttl', 21600),
            'audiences'           => array_map(
                static fn (string $key, string $label): array => ['key' => $key, 'label' => $label],
                array_keys(Note::AUDIENCES),
                Note::AUDIENCES
            ),
            'close_friends_count' => Note::closeFriendsCount($uid),
        ];
    }
}
