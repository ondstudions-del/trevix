<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Models\Conversation;
use Trevix\Services\E2eeService;

/** Claves del cifrado de extremo a extremo de los chats (las usa la app; ver E2eeService). */
final class E2eeController extends ApiController
{
    /** GET /me/keys — si la cuenta ya configuró el cifrado, su clave pública y la sal del PIN. */
    public function mine(): never
    {
        Reply::ok(E2eeService::status($this->uid()));
    }

    /** PUT /me/keys {public_key, backup?: {blob, salt, auth}} — registra la clave (o una nueva). */
    public function register(): never
    {
        $backup = Input::raw('backup');
        Reply::ok(E2eeService::register($this->uid(), Input::str('public_key'), is_array($backup) ? $backup : null));
    }

    /** PUT /me/keys/backup {blob, salt, auth} — nueva copia con otro PIN. */
    public function backup(): never
    {
        Reply::ok(E2eeService::saveBackup($this->uid(), [
            'blob' => Input::str('blob'), 'salt' => Input::str('salt'), 'auth' => Input::str('auth'),
        ]) + ['message' => 'Cambiaste el PIN del cifrado.']);
    }

    /** POST /me/keys/recover {auth} — copia cifrada de la clave si la prueba del PIN es correcta. */
    public function recover(): never
    {
        Reply::ok(E2eeService::recover($this->uid(), Input::str('auth')));
    }

    /** GET /conversations/{id}/keys */
    public function conversation(string $id): never
    {
        $uid = $this->uid();
        Reply::ok(E2eeService::conversationKeys($uid, $this->find((int) $id, $uid)));
    }

    /** POST /conversations/{id}/keys {epoch, keys: [{user_id, key_id, wrapped}]} — nueva época de la clave del chat. */
    public function rotate(string $id): never
    {
        $uid = $this->uid();
        $keys = Input::raw('keys');
        if (!is_array($keys) || $keys === []) {
            throw ActionError::field('keys', 'Faltan las claves del chat.');
        }
        Reply::ok(E2eeService::rotate($uid, $this->find((int) $id, $uid), Input::int('epoch'), array_values($keys)));
    }

    private function find(int $id, int $uid): array
    {
        $conversation = $id > 0 ? Conversation::findFor($id, $uid) : null;
        if ($conversation === null) {
            $this->notFound('Esta conversación no existe o no participas en ella.');
        }
        return $conversation;
    }
}
