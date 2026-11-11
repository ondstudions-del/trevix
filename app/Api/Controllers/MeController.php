<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Kernel;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Lang;
use Trevix\Core\Request;
use Trevix\Models\ApiToken;
use Trevix\Models\Appeal;
use Trevix\Models\Block;
use Trevix\Models\Follow;
use Trevix\Models\Post;
use Trevix\Models\User;
use Trevix\Models\UserProfile;
use Trevix\Models\Warning;
use Trevix\Services\AppealService;
use Trevix\Services\ProfileDetailsService;
use Trevix\Services\ProfileService;
use Trevix\Services\RelationshipService;
use Trevix\Services\SettingsService;
use Trevix\Services\VerificationService;

/** La propia cuenta: perfil, imágenes, ajustes, solicitudes, guardados y baja. */
final class MeController extends ApiController
{
    private const PROFILE_FIELDS = ['display_name', 'username', 'bio', 'website', 'country', 'birth_date'];

    /** GET /me */
    public function show(): never
    {
        Reply::ok(Present::me($this->user()));
    }

    /** GET /me/counts — avisos sin leer, solicitudes y mensajes (para los distintivos de la app). */
    public function counts(): never
    {
        \Trevix\Models\Conversation::markDelivered($this->uid());
        Reply::ok(Present::counts($this->user()));
    }

    /**
     * PATCH /me {display_name?, username?, bio?, website?, country?, birth_date?, is_private?, account_type?, creator_category?}
     * — solo cambia lo enviado.
     */
    public function update(): never
    {
        $user = $this->user();
        $input = [];
        foreach (self::PROFILE_FIELDS as $field) {
            $input[$field] = Input::has($field) ? Input::str($field) : (string) ($user[$field] ?? '');
        }
        $input['is_private'] = Input::bool('is_private') ?? !empty($user['is_private']);
        foreach (['account_type', 'creator_category'] as $field) {
            if (Input::has($field)) {
                $input[$field] = Input::str($field);
            }
        }
        $this->saveProfile($user, $input, false, false);
    }

    /** POST /me/avatar · POST /me/cover (multipart, campo «avatar» o «cover»). */
    public function uploadImage(string $kind): never
    {
        if (!isset($_FILES[$kind]) || (int) ($_FILES[$kind]['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
            throw ActionError::field($kind, t('Adjunta la imagen en el campo «{field}» (multipart/form-data).', ['field' => $kind]));
        }
        $user = $this->user();
        $this->saveProfile($user, $this->currentProfile($user), false, false);
    }

    /** DELETE /me/avatar · DELETE /me/cover */
    public function deleteImage(string $kind): never
    {
        $_FILES = [];
        $user = $this->user();
        $this->saveProfile($user, $this->currentProfile($user), $kind === 'avatar', $kind === 'cover');
    }

    /** GET /me/details — datos personales completos y las opciones de cada selector. */
    public function details(): never
    {
        $user = $this->user();
        Reply::ok([
            'details' => Present::details(ProfileDetailsService::visibleTo($user, UserProfile::forUser((int) $user['id']), (int) $user['id'], null)),
            'options' => ProfileDetailsService::options(),
        ]);
    }

    /**
     * PUT /me/details {city?, hometown?, relationship_status?, gender?, interests?: string[], links?: {title,url}[],
     * contacts?: {type,value}[], details_audience?, show_birth_year?, birth_date?} — solo cambia lo enviado.
     */
    public function saveDetails(): never
    {
        $input = [];
        foreach (['city', 'hometown', 'relationship_status', 'gender', 'details_audience', 'birth_date'] as $field) {
            if (Input::has($field)) {
                $input[$field] = Input::str($field);
            }
        }
        foreach (['interests', 'links', 'contacts'] as $field) {
            if (Input::has($field)) {
                $input[$field] = Input::raw($field);
            }
        }
        if (Input::bool('show_birth_year') !== null) {
            $input['show_birth_year'] = Input::bool('show_birth_year');
        }
        ProfileDetailsService::save($this->user(), $input);
        $user = $this->fresh();
        Reply::ok([
            'message' => 'Guardamos tus datos personales.',
            'details' => Present::details(ProfileDetailsService::visibleTo($user, UserProfile::forUser((int) $user['id']), (int) $user['id'], null)),
        ]);
    }

    /** PUT /me/profile-song {song_id, song_start?} · DELETE /me/profile-song — canción que suena al tocarla en tu perfil. */
    public function profileSong(): never
    {
        $uid = $this->uid();
        if (Request::method() === 'DELETE') {
            ProfileDetailsService::removeSong($uid);
            Reply::ok(['message' => 'Quitaste la canción de tu perfil.', 'song' => null]);
        }
        ProfileDetailsService::setSong($uid, Input::int('song_id'), Input::int('song_start'));
        Reply::ok(['message' => 'Tu perfil ya tiene canción.', 'song' => Present::profileSong(UserProfile::forUser($uid)['song'])]);
    }

    /**
     * GET /me/verification — insignia, requisitos con su avance, última solicitud y si puede pedirlo.
     * POST {category, full_name, note?} — pedir el verificado (los requisitos se comprueban aquí).
     * DELETE — cancelar la solicitud en revisión.
     */
    public function verification(): never
    {
        $user = $this->user();
        $method = Request::method();
        if ($method === 'POST') {
            $status = VerificationService::apply($user, [
                'category'  => Input::str('category'),
                'full_name' => Input::str('full_name'),
                'note'      => Input::str('note', false),
            ]);
            Reply::ok(Present::admin($status) + ['message' => 'Enviamos tu solicitud. Te avisaremos cuando el equipo la revise.']);
        }
        if ($method === 'DELETE') {
            Reply::ok(Present::admin(VerificationService::cancel($user)) + ['message' => 'Cancelaste tu solicitud de verificado.']);
        }
        Reply::ok(Present::admin(VerificationService::status($user)));
    }

    /** GET /me/warnings — advertencias del equipo (las vigentes de los últimos días impiden pedir el verificado). */
    public function warnings(): never
    {
        $uid = $this->uid();
        $days = VerificationService::rules()['warning_days'];
        Reply::ok([
            'warnings'     => array_map(static fn (array $w) => [
                'id'          => $w['id'],
                'reason'      => $w['reason'],
                'about'       => $w['target_type'],
                'created_at'  => Present::date($w['created_at']),
                'revoked'     => $w['revoked'],
                'active'      => !$w['revoked'] && strtotime((string) $w['created_at']) > time() - $days * 86400,
            ], Warning::forUser($uid)),
            'active_count' => Warning::activeCountSince($uid, $days),
            'days'         => $days,
        ]);
    }

    /** GET /me/appeals — apelaciones de la cuenta (suspensiones y advertencias) con la decisión del equipo. */
    public function appeals(): never
    {
        Reply::ok(array_map(static fn (array $a) => [
            'id'              => (int) $a['id'],
            'type'            => $a['type'],
            'warning_id'      => $a['warning_id'] !== null ? (int) $a['warning_id'] : null,
            'sanction_reason' => $a['sanction_reason'],
            'message'         => $a['message'],
            'status'          => $a['status'],
            'resolution_note' => $a['status'] !== 'pending' ? $a['resolution_note'] : null,
            'created_at'      => Present::date($a['created_at']),
            'reviewed_at'     => $a['reviewed_at'] !== null ? Present::date($a['reviewed_at']) : null,
        ], Appeal::forUser($this->uid())));
    }

    /** POST /me/appeals {warning_id, message} — apelar una advertencia vigente. */
    public function appealWarning(): never
    {
        $id = AppealService::appealWarning($this->user(), Input::int('warning_id'), Input::str('message', false));
        Reply::ok(['appeal_id' => $id, 'message' => 'Enviamos tu apelación. El equipo la revisará y te avisaremos.'], [], 201);
    }

    /** PUT /me/locale {locale: es|en} — idioma preferido de la cuenta (el de la web; la app envía Accept-Language). */
    public function locale(): never
    {
        $locale = Input::str('locale');
        if (!Lang::isSupported($locale)) {
            throw ActionError::field('locale', 'Elige un idioma disponible.');
        }
        User::setLocale($this->uid(), $locale);
        Reply::ok(['locale' => $locale]);
    }

    /** PATCH /me/account {username?, email?, phone?, current_password} — la contraseña es obligatoria para cambiar el correo. */
    public function account(): never
    {
        $user = $this->user();
        $result = SettingsService::updateAccount(
            $user,
            Input::has('username') ? Input::str('username') : (string) $user['username'],
            Input::has('email') ? Input::str('email') : (string) $user['email'],
            Input::str('current_password', false),
            'current_password',
            Input::has('phone') ? Input::str('phone') : null
        );
        Reply::ok([
            'changed'  => $result['changed'],
            'message'  => $result['changed'] ? implode(' ', array_map('t', $result['messages'])) : 'No hiciste cambios.',
            'warning'  => $result['error'],
            'user'     => Present::me($this->fresh()),
        ]);
    }

    /** POST /me/email/verification — reenvía el enlace de confirmación. */
    public function resendVerification(): never
    {
        $result = SettingsService::resendVerification($this->user());
        if ($result['type'] === 'error') {
            throw new ActionError($result['message'], 502);
        }
        Reply::ok(['message' => $result['message']]);
    }

    /**
     * PUT /me/password {current_password, password, password_confirmation} — cierra las sesiones de los
     * demás dispositivos (web y app); esta sesión sigue abierta.
     */
    public function password(): never
    {
        $user = $this->user();
        $hash = SettingsService::changePassword($user, Input::str('current_password', false), Input::str('password', false), Input::str('password_confirmation', false));
        $tokenId = (int) Kernel::token()['id'];
        ApiToken::refreshFingerprint($tokenId, $hash);
        ApiToken::revokeAllFor((int) $user['id'], $tokenId);
        Reply::ok(['message' => 'Tu contraseña se actualizó. Cerramos la sesión en tus otros dispositivos.']);
    }

    /** PATCH /me/privacy {is_private?, show_activity?, read_receipts?, message_privacy?} */
    public function privacy(): never
    {
        $message = SettingsService::updatePrivacy(
            $this->user(),
            Input::bool('is_private'),
            Input::bool('show_activity'),
            Input::has('message_privacy') ? Input::str('message_privacy') : null,
            Input::bool('read_receipts')
        );
        Reply::ok(['message' => $message ?? 'No hiciste cambios.', 'user' => Present::me($this->fresh())]);
    }

    /** PATCH /me/notification-settings {notify_follows?, notify_likes?, notify_comments?, notify_mentions?} */
    public function notificationSettings(): never
    {
        $prefs = [];
        foreach (SettingsService::NOTIFY_FIELDS as $field) {
            $prefs[$field] = Input::bool($field);
        }
        $changed = SettingsService::updateNotifications($this->user(), $prefs);
        Reply::ok([
            'message' => $changed ? 'Guardamos tus preferencias de notificaciones.' : 'No hiciste cambios.',
            'user'    => Present::me($this->fresh()),
        ]);
    }

    /** GET /me/blocked */
    public function blocked(): never
    {
        Reply::ok(array_map(static fn (array $u) => Present::user($u) + ['blocked_at' => Present::date($u['blocked_at'] ?? null)], Block::listFor($this->uid())));
    }

    /** GET /me/follow-requests?page= */
    public function followRequests(): never
    {
        $result = Follow::pendingRequests($this->uid(), $this->pageNumber(), $this->limit('people_page', 30));
        Reply::ok(
            array_map(static fn (array $u) => Present::user($u) + ['requested_at' => Present::date($u['requested_at'] ?? null)], $result['users']),
            $this->nextPage($result['hasMore'])
        );
    }

    /** POST /me/follow-requests/{id}/accept · /reject */
    public function resolveRequest(string $id, string $action): never
    {
        $result = RelationshipService::follow($this->uid(), (int) $id, $action);
        Reply::ok(['message' => $result['message'], 'user_id' => (int) $result['target']['id']]);
    }

    /** GET /me/saved?page= */
    public function saved(): never
    {
        $paging = $this->paging();
        $result = Post::saved($this->uid(), $paging['page'], $paging['limit']);
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** POST /me/deactivate {password} — cierra todas las sesiones de la app. */
    public function deactivate(): never
    {
        $user = $this->user();
        SettingsService::deactivate($user, Input::str('password', false), 'password');
        ApiToken::revokeAllFor((int) $user['id']);
        Reply::ok(['message' => 'Tu cuenta quedó desactivada. Vuelve cuando quieras: solo tienes que iniciar sesión.']);
    }

    /** DELETE /me {password, confirm_username} — eliminación definitiva. */
    public function destroy(): never
    {
        SettingsService::deleteAccount($this->user(), Input::str('password', false), Input::str('confirm_username'), 'password', 'confirm_username');
        Reply::ok(['message' => 'Tu cuenta y tu contenido se eliminaron de forma permanente.']);
    }

    private function saveProfile(array $user, array $input, bool $removeAvatar, bool $removeCover): never
    {
        $result = ProfileService::update($user, $input, $removeAvatar, $removeCover);
        $accepted = $result['accepted'];
        Reply::ok([
            'message' => t('Tu perfil se actualizó.') . ($accepted > 0 ? ' ' . tn($accepted, 'Aprobamos {n} solicitud pendiente.', 'Aprobamos {n} solicitudes pendientes.') : ''),
            'user'    => Present::me($this->fresh()),
        ]);
    }

    private function currentProfile(array $user): array
    {
        $input = [];
        foreach (self::PROFILE_FIELDS as $field) {
            $input[$field] = (string) ($user[$field] ?? '');
        }
        $input['is_private'] = !empty($user['is_private']);
        return $input;
    }

    /** La cuenta recién guardada (para devolverla actualizada). */
    private function fresh(): array
    {
        $user = User::findForSession($this->uid()) ?? throw new ActionError('Tu cuenta ya no está disponible.', 401);
        unset($user['password_hash']);
        Auth::actingAs($user);
        return $user;
    }
}
