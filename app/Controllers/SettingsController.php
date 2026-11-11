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
use Trevix\Services\SettingsService;

final class SettingsController extends Controller
{
    public const SECTIONS = [
        'account'       => ['label' => 'Cuenta', 'icon' => 'circle-user', 'phase' => 2],
        'security'      => ['label' => 'Contraseña y seguridad', 'icon' => 'shield-check', 'phase' => 2],
        'privacy'       => ['label' => 'Privacidad', 'icon' => 'lock', 'phase' => 4],
        'notifications' => ['label' => 'Notificaciones', 'icon' => 'bell', 'phase' => 5],
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
