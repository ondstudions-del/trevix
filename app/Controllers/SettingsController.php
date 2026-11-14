<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Block;
use Trevix\Models\PrivateChat;
use Trevix\Services\PrivateChatService;
use Trevix\Services\SettingsService;

final class SettingsController extends Controller
{
    public const SECTIONS = [
        'account'       => ['label' => 'Cuenta', 'icon' => 'circle-user', 'phase' => 2],
        'security'      => ['label' => 'Contraseña y seguridad', 'icon' => 'shield-check', 'phase' => 2],
        'privacy'       => ['label' => 'Privacidad', 'icon' => 'lock', 'phase' => 4],
        'notifications' => ['label' => 'Notificaciones', 'icon' => 'bell', 'phase' => 5],
        'chats'         => ['label' => 'Chats privados', 'icon' => 'lock-keyhole', 'phase' => 5],
        'appearance'    => ['label' => 'Apariencia y accesibilidad', 'icon' => 'palette', 'phase' => 1],
    ];

    /** Fase a partir de la cual cada sección guarda datos en el servidor. */
    private const IMPLEMENTED_PHASE = 5;

    /** Interruptores de la sección Notificaciones: campo del formulario => columna de users. */
    public const NOTIFY_FIELDS = [
        'notify_follows'  => ['Seguidores y comunidades', 'Cuando alguien empiece a seguirte o acepte tu solicitud, pida unirse a una comunidad que moderas o te acepte en una. Las solicitudes de seguimiento pendientes siempre se muestran.'],
        'notify_likes'    => ['Me gusta y compartidos', 'Cuando a alguien le guste o comparta tu publicación.'],
        'notify_comments' => ['Comentarios y respuestas', 'Cuando comenten tus publicaciones o respondan a tus comentarios.'],
        'notify_mentions' => ['Menciones', 'Cuando alguien te mencione con @ en una publicación o un comentario.'],
    ];

    public function index(): void
    {
        Authenticate::handle();

        $section = Request::queryIn('section', array_keys(self::SECTIONS), 'account');

        if (Request::isPost()) {
            if (self::SECTIONS[$section]['phase'] > self::IMPLEMENTED_PHASE) {
                $this->rejectWritesUntil(self::SECTIONS[$section]['phase']);
            }
            VerifyCsrf::handle();
            $user = $this->requireUser();
            match (Request::text('action')) {
                'account'             => $this->updateAccount($user),
                'resend_verification' => $this->resendVerification($user),
                'deactivate'          => $this->deactivate($user),
                'delete'              => $this->deleteAccount($user),
                'password'            => $this->changePassword($user),
                'sessions'            => $this->logoutOtherSessions($user),
                'privacy'             => $this->updatePrivacy($user),
                'notifications'       => $this->updateNotifications($user),
                'private_pin'         => $this->privatePin($user),
                'private_export'      => $this->privateExport($user),
                'private_empty'       => $this->privateEmpty($user),
                'private_reset'       => $this->privateReset($user),
                'private_disable'     => $this->privateDisable($user),
                default               => Response::abort(400, 'Acción no válida.'),
            };
        }

        $privacy = ['blocked' => [], 'pendingRequests' => 0];
        if ($section === 'privacy' && Auth::check()) {
            $privacy = [
                'blocked'         => Block::listFor((int) Auth::id()),
                'pendingRequests' => (int) (Auth::user()['pending_requests'] ?? 0),
            ];
        }

        $this->render('pages/settings', [
            'privacy'     => $privacy,
            'notifyFields' => self::NOTIFY_FIELDS,
            'title'       => t('Configuración') . ' · TREVIX',
            'activeNav'   => 'settings',
            'section'     => $section,
            'sections'    => self::SECTIONS,
            'panelOpen'   => Request::query('section') !== '',
            'passwordMin' => (int) Config::get('app.security.password_min_length'),
            'errors'      => Session::pull('_errors', []),
            'old'         => Session::pull('_old', []),
            'canEdit'     => Auth::check(),
            'isAdmin'     => Auth::hasRole('admin'),
            'hasPrivatePin' => Auth::check() && PrivateChat::hasPin((int) Auth::id()),
            'layoutWide'  => true,
        ], 'layouts/app');
    }

    private function updateAccount(array $user): never
    {
        $back = $this->sectionUrl('account');
        $username = mb_strtolower(Request::text('username'));
        $email = mb_strtolower(Request::text('email'));
        $phone = Request::text('phone');
        $result = $this->settle(
            static fn () => SettingsService::updateAccount($user, $username, $email, Request::text('current_password', false), 'current_password', $phone),
            $back,
            ['username' => $username, 'email' => $email, 'phone' => $phone]
        );

        if (!$result['changed']) {
            Session::flash('info', 'No hiciste cambios.');
        }
        if ($result['error'] !== null) {
            Session::flash('error', $result['error']);
        }
        if ($result['messages'] !== []) {
            Session::flash('success', implode(' ', array_map('t', $result['messages'])));
        }
        Response::redirect($back);
    }

    private function updatePrivacy(array $user): never
    {
        $back = $this->sectionUrl('privacy');
        $message = $this->settle(static fn () => SettingsService::updatePrivacy(
            $user,
            Request::text('is_private') === '1',
            Request::text('show_activity') === '1',
            Request::text('message_privacy'),
            Request::text('read_receipts') === '1'
        ), $back);
        $message === null ? Session::flash('info', 'No hiciste cambios.') : Session::flash('success', $message);
        Response::redirect($back);
    }

    private function updateNotifications(array $user): never
    {
        $prefs = [];
        foreach (array_keys(self::NOTIFY_FIELDS) as $field) {
            $prefs[$field] = Request::text($field) === '1';
        }
        SettingsService::updateNotifications($user, $prefs)
            ? Session::flash('success', 'Guardamos tus preferencias de notificaciones.')
            : Session::flash('info', 'No hiciste cambios.');
        Response::redirect($this->sectionUrl('notifications'));
    }

    private function resendVerification(array $user): never
    {
        $back = $this->sectionUrl('account');
        try {
            $result = SettingsService::resendVerification($user);
            Session::flash($result['type'], $result['message']);
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        Response::redirect($back);
    }

    private function changePassword(array $user): never
    {
        $back = $this->sectionUrl('security');
        $hash = $this->settle(static fn () => SettingsService::changePassword(
            $user,
            Request::text('current_password', false),
            Request::text('password', false),
            Request::text('password_confirmation', false)
        ), $back);
        Auth::refreshFingerprint($hash);
        Session::flash('success', 'Tu contraseña se actualizó. Cerramos la sesión en tus otros dispositivos.');
        Response::redirect($back);
    }

    /** Volver a generar el hash invalida la huella de las sesiones abiertas en otros dispositivos (web y app). */
    private function logoutOtherSessions(array $user): never
    {
        $back = $this->sectionUrl('security');
        $hash = $this->settle(
            static fn () => SettingsService::rehashPassword($user, Request::text('sessions_password', false), 'sessions_password'),
            $back
        );
        Auth::refreshFingerprint($hash);
        Session::flash('success', 'Cerramos la sesión en todos tus otros dispositivos.');
        Response::redirect($back);
    }

    private function deactivate(array $user): never
    {
        $this->settle(
            static fn () => SettingsService::deactivate($user, Request::text('deactivate_password', false), 'deactivate_password'),
            $this->sectionUrl('account')
        );
        Auth::logout();
        Session::start();
        Session::flash('success', 'Tu cuenta quedó desactivada. Vuelve cuando quieras: solo tienes que iniciar sesión.');
        Response::redirect(url('login.php'));
    }

    private function deleteAccount(array $user): never
    {
        $this->settle(static fn () => SettingsService::deleteAccount(
            $user,
            Request::text('delete_password', false),
            Request::text('delete_confirm'),
            'delete_password',
            'delete_confirm'
        ), $this->sectionUrl('account'));
        Auth::logout();
        Session::start();
        Session::flash('success', 'Tu cuenta y tu contenido se eliminaron de forma permanente.');
        Response::redirect(url('login.php'));
    }

    /** Crea o cambia el PIN de los chats privados. */
    private function privatePin(array $user): never
    {
        $back = $this->sectionUrl('chats');
        $uid = (int) $user['id'];
        $had = PrivateChat::hasPin($uid);
        $this->settle(static fn () => PrivateChatService::setPin($uid, Request::text('pin'), Request::text('pin_confirmation'), Request::text('current_pin')), $back);
        Session::flash('success', $had ? 'Cambiaste el PIN de tus chats privados.' : 'Creaste el PIN de tus chats privados.');
        Response::redirect($back);
    }

    /** Descarga los chats privados en texto, con el PIN o (si se olvidó) con la contraseña de la cuenta. */
    private function privateExport(array $user): never
    {
        $uid = (int) $user['id'];
        $secret = Request::text('export_secret', false);
        $this->settle(static function () use ($user, $uid, $secret): void {
            $unlocked = PrivateChatService::webUnlocked($uid);
            if (!$unlocked && PrivateChatService::validPin($secret)) {
                PrivateChatService::unlock($uid, $secret, 'export_secret');
                $unlocked = true;
            }
            PrivateChatService::exportAllowed($user, $unlocked, $secret, 'export_secret');
        }, $this->sectionUrl('chats'));
        $text = PrivateChatService::exportText($uid);
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        header('Content-Type: text/plain; charset=utf-8');
        header('Content-Disposition: attachment; filename="trevix-chats-privados-' . date('Y-m-d') . '.txt"');
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        echo "\xEF\xBB\xBF" . $text;
        exit;
    }

    /** Vacía los chats privados (con el PIN). */
    private function privateEmpty(array $user): never
    {
        $back = $this->sectionUrl('chats');
        $uid = (int) $user['id'];
        $count = $this->settle(static function () use ($uid): int {
            if (!PrivateChatService::webUnlocked($uid)) {
                PrivateChatService::unlock($uid, Request::text('empty_pin'), 'empty_pin');
            }
            return PrivateChatService::emptyAll($uid);
        }, $back);
        Session::flash('success', $count > 0 ? 'Vaciaste tus chats privados.' : 'No tenías chats privados.');
        Response::redirect($back);
    }

    /** Olvidé mi PIN: con la contraseña se vacían los chats privados y se crea un PIN nuevo. */
    private function privateReset(array $user): never
    {
        $back = $this->sectionUrl('chats');
        try {
            PrivateChatService::reset($user, Request::text('reset_password', false), Request::text('reset_pin'), Request::text('reset_pin_confirmation'));
        } catch (ActionError $e) {
            if ($e->fields === []) {
                Session::flash('error', $e->getMessage());
                Response::redirect($back);
            }
            $fields = [];
            foreach ($e->fields as $field => $message) {
                $fields['reset_' . $field] = $message;
            }
            $this->backWithErrors($back, $fields, []);
        }
        PrivateChatService::webLock();
        Session::flash('success', 'Vaciaste tus chats privados y creaste un PIN nuevo.');
        Response::redirect($back);
    }

    /** Desactiva los chats privados (con el PIN): vuelven a la bandeja y se borra el PIN. */
    private function privateDisable(array $user): never
    {
        $back = $this->sectionUrl('chats');
        $uid = (int) $user['id'];
        $this->settle(static function () use ($uid): int {
            if (!PrivateChatService::webUnlocked($uid)) {
                PrivateChatService::unlock($uid, Request::text('disable_pin'), 'disable_pin');
            }
            return PrivateChatService::disable($uid);
        }, $back);
        PrivateChatService::webLock();
        Session::flash('success', 'Desactivaste los chats privados: tus chats volvieron a la bandeja.');
        Response::redirect($back);
    }

    /** Ejecuta la acción; un error de campo vuelve al formulario y uno general se muestra como aviso. */
    private function settle(callable $action, string $back, array $old = []): mixed
    {
        try {
            return $action();
        } catch (ActionError $e) {
            if ($e->fields === []) {
                Session::flash('error', $e->getMessage());
                Response::redirect($back);
            }
            $this->backWithErrors($back, $e->fields, $old);
        }
    }

    private function sectionUrl(string $section): string
    {
        return url('settings.php', ['section' => $section]);
    }
}
