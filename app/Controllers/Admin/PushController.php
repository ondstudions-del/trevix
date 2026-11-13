<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Deferred;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AuditLog;
use Trevix\Models\PushCampaign;
use Trevix\Models\PushDevice;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Services\Fcm;
use Trevix\Services\PushNotifier;

/**
 * Avisos push (solo administradores): envía un aviso a una persona o a todos los teléfonos (o solo Android o solo
 * iPhone) por Firebase Cloud Messaging, y muestra los teléfonos registrados y el resultado de cada envío. El envío
 * corre después de responder, por tandas; si el servidor lo corta, se puede continuar desde donde quedó.
 */
final class PushController extends AdminController
{
    public const AUDIENCES = [
        'all'     => 'Todos los teléfonos',
        'android' => 'Solo Android',
        'ios'     => 'Solo iPhone',
        'user'    => 'Una persona',
    ];

    public function handle(): void
    {
        $this->guard('push');
        if (Request::isPost()) {
            $this->act();
        }
        $live = $this->staff() !== null;
        $this->page('push', 'push', [
            'configured' => Fcm::configured(),
            'client'     => Fcm::clientConfig(),
            'stats'      => $live ? PushDevice::stats() : null,
            'campaigns'  => $live ? PushCampaign::recent(20) : [],
        ]);
    }

    private function act(): never
    {
        $back = $this->sectionUrl('push');
        $staff = $this->beginAction('admin', $back);
        try {
            switch (Request::text('action')) {
                case 'send':
                    $this->send($staff);
                    break;
                case 'resume':
                    $campaign = PushCampaign::find((int) Request::input('id', 0));
                    if ($campaign === null || !PushCampaign::stalled($campaign)) {
                        throw new DomainException('Ese envío ya terminó o sigue en curso.');
                    }
                    AuditLog::record((int) $staff['id'], 'push.resume', 'push_campaign', (int) $campaign['id']);
                    Deferred::run(static fn () => PushNotifier::campaign((int) $campaign['id']));
                    Session::flash('success', 'Continuamos el envío desde donde quedó.');
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($back);
    }

    private function send(array $staff): void
    {
        if (!Fcm::configured()) {
            throw new DomainException('Firebase Cloud Messaging no está configurado en el servidor.');
        }
        $audience = Request::text('audience');
        if (!array_key_exists($audience, self::AUDIENCES)) {
            throw new DomainException('Elige a quién enviar el aviso.');
        }
        $title = $this->line(Request::text('title', false), 80);
        $body = $this->line(Request::text('body', false), 240);
        if ($title === '' || $body === '') {
            throw new DomainException('Escribe el título y el texto del aviso.');
        }
        $link = $this->link(Request::text('link'));
        $targetId = null;
        if ($audience === 'user') {
            $target = User::findByUsername(ltrim(Request::text('username'), '@'));
            if ($target === null || ($target['status'] ?? 'active') !== 'active') {
                throw new DomainException('No encontramos una cuenta activa con ese nombre de usuario.');
            }
            $targetId = (int) $target['id'];
        }
        $platform = in_array($audience, PushDevice::PLATFORMS, true) ? $audience : null;
        $total = PushDevice::count($platform, $targetId);
        if ($total === 0) {
            throw new DomainException($audience === 'user'
                ? 'Esa persona no tiene la app con avisos activos en ningún teléfono.'
                : 'Todavía no hay teléfonos registrados para ese envío.');
        }
        $key = (string) $staff['id'];
        if (RateLimit::tooManyAttempts('push_campaign', $key)) {
            throw new DomainException(t('Enviaste muchos avisos seguidos. Espera {min} min.', [
                'min' => (int) ceil(RateLimit::availableIn('push_campaign', $key) / 60),
            ]));
        }
        RateLimit::hit('push_campaign', $key);
        $id = PushCampaign::create((int) $staff['id'], $title, $body, $link, $audience, $targetId, $total);
        AuditLog::record((int) $staff['id'], 'push.send', 'push_campaign', $id, [
            'audience' => $audience, 'target_user_id' => $targetId, 'devices' => $total, 'title' => $title,
        ]);
        Deferred::run(static fn () => PushNotifier::campaign($id));
        Session::flash('success', t('Enviando el aviso a {n} teléfonos. El resultado aparece abajo en unos segundos.', ['n' => $total]));
    }

    private function line(string $text, int $max): string
    {
        return mb_substr(trim((string) preg_replace('/\s+/u', ' ', $this->cleanText($text))), 0, $max);
    }

    /**
     * Pantalla que abre el aviso: una ruta de TREVIX (post.php?id=5) o un enlace de este sitio, que se guarda como ruta.
     * Vacío abre la app en el inicio.
     */
    private function link(string $raw): ?string
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }
        $base = rtrim(absolute_url(''), '/') . '/';
        if (str_starts_with($raw, $base)) {
            $raw = substr($raw, strlen($base));
        }
        $raw = ltrim($raw, '/');
        if (strlen($raw) > 255 || preg_match('#^[a-z0-9_-]+\.php(\?[A-Za-z0-9_\-=&%.@]*)?(\#[A-Za-z0-9_-]*)?$#', $raw) !== 1) {
            throw new DomainException('El enlace debe ser una página de TREVIX, por ejemplo post.php?id=5 o https://trevix.ond-s.com/profile.php?u=nombre.');
        }
        return $raw;
    }
}
