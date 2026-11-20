<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Database;
use Trevix\Core\Password;
use Trevix\Models\AuditLog;
use Trevix\Models\Notification;
use Trevix\Models\OAuthApp;
use Trevix\Models\User;

/**
 * Apps de desarrolladores: solicitud, aprobación y OAuth.
 * Solo se comparte perfil público (foto, usuario, nombre) y acceso a la plataforma.
 * No se comparten contraseñas ni datos cifrados.
 */
final class OAuthService
{
    public static function presentApp(array $app, bool $ownerView = false): array
    {
        $out = [
            'id'            => (int) $app['id'],
            'name'          => (string) ($app['name'] ?? ''),
            'description'   => (string) ($app['description'] ?? ''),
            'icon_url'      => !empty($app['icon_path']) ? absolute_url((string) $app['icon_path']) : null,
            'platform'      => (string) ($app['platform'] ?? 'android'),
            'package_name'  => $app['package_name'] ?? null,
            'website_url'   => $app['website_url'] ?? null,
            'redirect_uris' => array_values(array_filter(array_map('trim', explode("\n", (string) ($app['redirect_uris'] ?? ''))))),
            'client_id'     => (string) ($app['client_id'] ?? ''),
            'status'        => (string) ($app['status'] ?? 'pending'),
            'status_label'  => t(OAuthApp::STATUSES[$app['status'] ?? 'pending'] ?? (string) $app['status']),
            'review_note'   => $app['review_note'] ?? null,
            'created_at'    => $app['created_at'] ?? null,
            'logins_count'  => array_key_exists('logins_count', $app)
                ? (int) $app['logins_count']
                : ((int) ($app['id'] ?? 0) > 0 ? OAuthApp::loginsCount((int) $app['id']) : 0),
        ];
        if ($ownerView) {
            $out['owner_id'] = (int) ($app['owner_id'] ?? 0);
        }
        if (isset($app['username'])) {
            $out['owner'] = [
                'id'           => (int) $app['owner_id'],
                'username'     => $app['username'],
                'display_name' => $app['display_name'],
                'avatar_url'   => !empty($app['avatar_path']) ? absolute_url((string) $app['avatar_path']) : null,
                'is_verified'  => !empty($app['is_verified']),
            ];
        }
        return $out;
    }

    public static function listMine(array $user): array
    {
        if (!User::isDeveloper($user)) {
            throw new ActionError('Solo los creadores con categoría Desarrollador pueden gestionar apps.', 403);
        }
        return array_map(static fn (array $a) => self::presentApp($a, true), OAuthApp::forOwner((int) $user['id']));
    }

    /**
     * @param array{name:string, description:string, platform:string, package_name?:string, website_url?:string, redirect_uris:string} $input
     * @param list<array> $iconFiles MediaUpload::collect('icon')
     * @return array{message:string, app:array, client_secret:string}
     */
    public static function create(array $user, array $input, array $iconFiles = []): array
    {
        if (!User::isDeveloper($user)) {
            throw new ActionError('Cambia tu cuenta a Creador › Desarrollador para registrar apps.', 403);
        }
        $name = Guard::singleLine((string) ($input['name'] ?? ''), 80) ?? '';
        $description = Guard::singleLine((string) ($input['description'] ?? ''), 500) ?? '';
        $platform = (string) ($input['platform'] ?? '');
        if ($name === '') {
            throw ActionError::field('name', 'Escribe el nombre de la app.');
        }
        if ($description === '') {
            throw ActionError::field('description', 'Describe la app.');
        }
        if (!isset(OAuthApp::PLATFORMS[$platform])) {
            throw ActionError::field('platform', 'Elige Android, iOS o Web.');
        }
        $package = null;
        $website = null;
        if ($platform === 'web') {
            $website = trim((string) ($input['website_url'] ?? ''));
            if ($website === '' || !filter_var($website, FILTER_VALIDATE_URL) || !preg_match('#^https?://#i', $website)) {
                throw ActionError::field('website_url', 'Indica la URL https de tu app web.');
            }
        } else {
            $package = trim((string) ($input['package_name'] ?? ''));
            if ($package === '' || !preg_match('/^[a-zA-Z][a-zA-Z0-9._]{1,198}$/', $package)) {
                throw ActionError::field('package_name', 'Indica el paquete de la app (ej. com.empresa.app).');
            }
        }
        $redirects = trim((string) ($input['redirect_uris'] ?? ''));
        $lines = array_values(array_filter(array_map('trim', preg_split('/\r\n|\r|\n/', $redirects) ?: [])));
        if ($lines === []) {
            throw ActionError::field('redirect_uris', 'Añade al menos una URL de redirección OAuth.');
        }
        foreach ($lines as $uri) {
            if (!filter_var($uri, FILTER_VALIDATE_URL)) {
                throw ActionError::field('redirect_uris', 'Cada redirección debe ser una URL válida.');
            }
        }
        $iconPath = null;
        if ($iconFiles !== []) {
            try {
                $iconPath = MediaUpload::storeAdImage($iconFiles[0])['path'] ?? null;
            } catch (\Throwable $e) {
                throw ActionError::field('icon', $e->getMessage());
            }
        }

        $clientId = 'tvx_' . bin2hex(random_bytes(16));
        $secret = 'tvs_' . bin2hex(random_bytes(24));
        $id = OAuthApp::create([
            'owner_id'           => (int) $user['id'],
            'name'               => $name,
            'description'        => $description,
            'icon_path'          => $iconPath,
            'platform'           => $platform,
            'package_name'       => $package,
            'website_url'        => $website,
            'redirect_uris'      => implode("\n", $lines),
            'client_id'          => $clientId,
            'client_secret_hash' => Password::hash($secret),
            'status'             => 'pending',
        ]);
        $app = OAuthApp::find($id) ?? [
            'id' => $id, 'owner_id' => (int) $user['id'], 'name' => $name, 'description' => $description,
            'icon_path' => $iconPath, 'platform' => $platform, 'package_name' => $package, 'website_url' => $website,
            'redirect_uris' => implode("\n", $lines), 'client_id' => $clientId, 'status' => 'pending',
            'review_note' => null, 'created_at' => date('Y-m-d H:i:s'),
        ];
        return [
            'message'       => t('Solicitud enviada. Cuando un administrador o moderador la apruebe, la API funcionará.'),
            'app'           => self::presentApp($app, true),
            'client_secret' => $secret,
        ];
    }

    public static function pendingForStaff(array $staff, int $page, string $status = 'pending'): array
    {
        if (!Auth::hasRole('moderator', $staff)) {
            throw new ActionError('Sin permiso.', 403);
        }
        if (!in_array($status, ['pending', 'approved', 'rejected', 'all'], true)) {
            $status = 'pending';
        }
        $result = OAuthApp::adminList($status, $page, 30);
        return [
            'items'   => array_map(static fn (array $a) => self::presentApp($a, true), $result['items']),
            'hasMore' => $result['hasMore'],
        ];
    }

    public static function approve(array $staff, int $id, ?string $note = null): array
    {
        return self::review($staff, $id, 'approved', $note);
    }

    public static function reject(array $staff, int $id, ?string $note = null): array
    {
        return self::review($staff, $id, 'rejected', $note);
    }

    private static function review(array $staff, int $id, string $status, ?string $note): array
    {
        if (!Auth::hasRole('moderator', $staff)) {
            throw new ActionError('Sin permiso.', 403);
        }
        $app = OAuthApp::find($id);
        if ($app === null || ($app['status'] ?? '') !== 'pending') {
            throw new ActionError('Esa solicitud ya no está pendiente.', 404);
        }
        $cleanNote = Guard::singleLine((string) $note, 500);
        if (!OAuthApp::review($id, $status, (int) $staff['id'], $cleanNote)) {
            throw new ActionError('No se pudo actualizar la solicitud.', 409);
        }
        AuditLog::record((int) $staff['id'], 'oauth.app_' . $status, 'oauth_app', $id, ['name' => $app['name']]);
        Notification::notifySystem(
            (int) $app['owner_id'],
            $status === 'approved' ? 'oauth_app_approved' : 'oauth_app_rejected',
            $id
        );
        $fresh = OAuthApp::find($id);
        return [
            'message' => $status === 'approved' ? t('App aprobada: la API ya funciona.') : t('Solicitud rechazada.'),
            'app'     => self::presentApp($fresh ?? $app, true),
        ];
    }

    /** Usuario autenticado autoriza una app aprobada → código de un solo uso. */
    public static function authorize(array $user, string $clientId, string $redirectUri, ?string $state = null): array
    {
        $app = self::requireApprovedApp($clientId);
        self::assertRedirectAllowed($app, $redirectUri);
        $code = bin2hex(random_bytes(24));
        OAuthApp::storeCode((int) $app['id'], (int) $user['id'], $code, $redirectUri);
        $sep = str_contains($redirectUri, '?') ? '&' : '?';
        $url = $redirectUri . $sep . 'code=' . rawurlencode($code);
        if ($state !== null && $state !== '') {
            $url .= '&state=' . rawurlencode($state);
        }
        return [
            'redirect_url' => $url,
            'code'         => $code,
            'app'          => self::presentApp($app),
        ];
    }

    /**
     * Intercambia código + client_secret por access_token.
     * @return array{access_token:string, token_type:string, expires_in:int, user:array}
     */
    public static function token(string $clientId, string $clientSecret, string $code, string $redirectUri): array
    {
        $app = self::requireApprovedApp($clientId);
        if (!Password::verify($clientSecret, (string) $app['client_secret_hash'])) {
            throw new ActionError('Credenciales de app inválidas.', 401);
        }
        self::assertRedirectAllowed($app, $redirectUri);
        $row = Database::transaction(static function () use ($code, $app, $redirectUri): array {
            $auth = OAuthApp::consumeCode($code);
            if ($auth === null || (int) $auth['app_id'] !== (int) $app['id'] || (string) $auth['redirect_uri'] !== $redirectUri) {
                throw new ActionError('Código inválido o caducado.', 400);
            }
            $token = 'tva_' . bin2hex(random_bytes(32));
            OAuthApp::storeToken((int) $app['id'], (int) $auth['user_id'], hash('sha256', $token));
            return ['token' => $token, 'user_id' => (int) $auth['user_id']];
        });
        $profile = User::findActiveById($row['user_id']);
        if ($profile === null) {
            throw new ActionError('Usuario no disponible.', 404);
        }
        return [
            'access_token' => $row['token'],
            'token_type'   => 'Bearer',
            'expires_in'   => 86400 * 30,
            'user'         => self::publicProfile($profile),
        ];
    }

    public static function userinfo(string $bearerToken): array
    {
        $hash = hash('sha256', $bearerToken);
        $row = OAuthApp::findToken($hash);
        if ($row === null) {
            throw new ActionError('Token inválido o caducado.', 401);
        }
        $profile = User::findActiveById((int) $row['user_id']);
        if ($profile === null) {
            throw new ActionError('Usuario no disponible.', 404);
        }
        return self::publicProfile($profile);
    }

    /** Solo lo que se comparte con apps de terceros (estilo Google). */
    public static function publicProfile(array $user): array
    {
        return [
            'id'           => (int) $user['id'],
            'username'     => $user['username'],
            'display_name' => $user['display_name'],
            'avatar_url'   => !empty($user['avatar_path']) ? absolute_url((string) $user['avatar_path']) : null,
            'platform'     => 'trevix',
        ];
    }

    public static function appPublicInfo(string $clientId): array
    {
        $app = OAuthApp::byClientId($clientId);
        if ($app === null) {
            throw new ActionError('App no encontrada.', 404);
        }
        return self::presentApp($app);
    }

    private static function requireApprovedApp(string $clientId): array
    {
        $app = OAuthApp::byClientId($clientId);
        if ($app === null) {
            throw new ActionError('App no encontrada.', 404);
        }
        if (($app['status'] ?? '') !== 'approved') {
            throw new ActionError('Esta app aún no está aprobada.', 403);
        }
        return $app;
    }

    private static function assertRedirectAllowed(array $app, string $redirectUri): void
    {
        $allowed = array_filter(array_map('trim', explode("\n", (string) $app['redirect_uris'])));
        if (!in_array($redirectUri, $allowed, true)) {
            throw new ActionError('URL de redirección no autorizada para esta app.', 400);
        }
    }
}
