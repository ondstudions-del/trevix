<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
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
    private const CIPHER = 'AES-256-CBC';

    public static function presentApp(array $app, bool $ownerView = false, bool $includeSecret = false): array
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
            $secret = self::decryptSecret((string) ($app['client_secret_enc'] ?? ''));
            $out['has_secret'] = $secret !== '';
            if ($includeSecret) {
                $out['client_secret'] = $secret !== '' ? $secret : null;
            }
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
        return array_map(
            static fn (array $a) => self::presentApp($a, true, true),
            OAuthApp::forOwner((int) $user['id'])
        );
    }

    /** Detalle para el dueño: claves, código HTML, pasos, política. */
    public static function showMine(array $user, int $id): array
    {
        if (!User::isDeveloper($user)) {
            throw new ActionError('Solo los creadores con categoría Desarrollador pueden gestionar apps.', 403);
        }
        $app = OAuthApp::find($id);
        if ($app === null || (int) $app['owner_id'] !== (int) $user['id']) {
            throw new ActionError('App no encontrada.', 404);
        }
        $presented = self::presentApp($app, true, true);
        return [
            'app'         => $presented,
            'integration' => self::integrationGuide($app, $presented),
        ];
    }

    /** Regenera la clave API (útil si la app se creó antes de guardar la clave cifrada). */
    public static function regenerateSecret(array $user, int $id): array
    {
        if (!User::isDeveloper($user)) {
            throw new ActionError('Solo los creadores con categoría Desarrollador pueden gestionar apps.', 403);
        }
        $app = OAuthApp::find($id);
        if ($app === null || (int) $app['owner_id'] !== (int) $user['id']) {
            throw new ActionError('App no encontrada.', 404);
        }
        $secret = 'tvs_' . bin2hex(random_bytes(24));
        OAuthApp::updateSecret($id, Password::hash($secret), self::encryptSecret($secret));
        $fresh = OAuthApp::find($id) ?? $app;
        return [
            'message'       => t('Nueva clave API generada. Actualízala en tu servidor.'),
            'app'           => self::presentApp($fresh, true, true),
            'client_secret' => $secret,
        ];
    }

    /** @return array{authorize_url:string, html_button:string, html_full:string, steps:list<string>, token_example:string, policy:list<string>, requirements:list<string>, responsibilities:list<string>, api_base:string} */
    public static function integrationGuide(array $app, ?array $presented = null): array
    {
        $presented ??= self::presentApp($app, true);
        $clientId = (string) ($presented['client_id'] ?? $app['client_id'] ?? '');
        $redirect = ($presented['redirect_uris'][0] ?? null) ?: 'https://tu-sitio.com/callback';
        $authorizeUrl = rtrim((string) Config::get('app.url', absolute_url('')), '/') . '/oauth/authorize.php'
            . '?client_id=' . rawurlencode($clientId)
            . '&redirect_uri=' . rawurlencode($redirect)
            . '&state=ESTADO_ALEATORIO';
        $apiBase = rtrim((string) Config::get('app.url', absolute_url('')), '/') . '/api/v1';
        $btnLabel = t('Iniciar sesión con TREVIX');
        $htmlButton = '<a href="' . htmlspecialchars($authorizeUrl, ENT_QUOTES, 'UTF-8') . '" '
            . 'style="display:inline-flex;align-items:center;gap:10px;padding:12px 18px;border-radius:12px;'
            . 'background:#7C3AED;color:#fff;font:600 15px/1.2 system-ui,sans-serif;text-decoration:none">'
            . htmlspecialchars($btnLabel, ENT_QUOTES, 'UTF-8') . '</a>';
        $htmlFull = "<!-- Botón «Iniciar sesión con TREVIX» -->\n"
            . $htmlButton . "\n"
            . "<!-- Tras Permitir, TREVIX redirige a tu redirect_uri con ?code=…&state=… -->\n";
        $platform = (string) ($presented['platform'] ?? 'web');
        $steps = match ($platform) {
            'web' => [
                t('1. Copia el HTML del botón e íntegralo en tu página de login o registro.'),
                t('2. Asegúrate de que redirect_uri coincida exactamente con una URL registrada en la app.'),
                t('3. En tu servidor, al recibir ?code=, llama a POST /api/v1/oauth/token con client_id, client_secret, code y redirect_uri.'),
                t('4. Guarda el access_token y usa GET /api/v1/oauth/userinfo con Authorization: Bearer para leer foto, usuario y nombre.'),
                t('5. Crea o vincula la sesión de tu propio sistema con esos datos. Nunca pidas ni guardes la contraseña de TREVIX.'),
            ],
            'ios' => [
                t('1. Abre el authorize_url en SFSafariViewController o ASWebAuthenticationSession.'),
                t('2. Registra el redirect_uri (custom scheme o universal link) en Mis apps y en tu proyecto Xcode.'),
                t('3. Al volver con ?code=, tu backend intercambia el código por access_token (nunca envíes client_secret desde el iPhone).'),
                t('4. Con el token, pide userinfo y crea la sesión local (foto, @usuario, nombre).'),
                t('5. La app debe estar aprobada; hasta entonces la API responde 403.'),
            ],
            default => [
                t('1. Abre el authorize_url en Custom Tabs o WebView segura (Chrome Custom Tabs).'),
                t('2. El redirect_uri (intent/app link) debe coincidir con el registrado y con el paquete de la app.'),
                t('3. Al recibir el code, tu backend hace POST /oauth/token con la clave secreta (solo en servidor).'),
                t('4. Usa el access_token con /oauth/userinfo para obtener foto, usuario y nombre.'),
                t('5. No empaquetes client_secret en el APK/AAB: cualquiera podría extraerlo.'),
            ],
        };
        $tokenExample = "POST {$apiBase}/oauth/token\n"
            . "Content-Type: application/json\n\n"
            . json_encode([
                'client_id'     => $clientId,
                'client_secret' => 'tvs_…',
                'code'          => 'CODIGO_RECIBIDO',
                'redirect_uri'  => $redirect,
            ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

        return [
            'authorize_url'    => $authorizeUrl,
            'html_button'      => $htmlButton,
            'html_full'        => $htmlFull,
            'steps'            => $steps,
            'token_example'    => $tokenExample,
            'api_base'         => $apiBase,
            'requirements'     => [
                t('Cuenta TREVIX con tipo Creador y categoría Desarrollador.'),
                t('App registrada con icono, nombre, descripción y paquete o URL web.'),
                t('Al menos una URL de redirección válida (https recomendado).'),
                t('Aprobación de un administrador o moderador de TREVIX.'),
                t('Usar HTTPS en producción para redirect_uri y llamadas a la API.'),
            ],
            'responsibilities' => [
                t('Eres responsable de proteger client_id y client_secret; no los publiques en repositorios abiertos ni en el cliente móvil.'),
                t('Solo puedes usar los datos compartidos (foto, usuario, nombre y acceso) para autenticar en tu producto.'),
                t('Debes informar a tus usuarios que inician sesión con TREVIX y qué datos recibes.'),
                t('Si detectas abuso o filtración de claves, regenera la clave y avisa a TREVIX.'),
                t('TREVIX puede revocar apps que incumplan estas reglas o las normas de la comunidad.'),
            ],
            'policy'           => [
                t('TREVIX solo comparte foto de perfil, nombre de usuario, nombre visible y acceso a la plataforma (estilo Google).'),
                t('Nunca se comparten contraseñas, datos cifrados, correo, teléfono ni contenido privado del usuario.'),
                t('El usuario debe consentir en la pantalla de autorización de TREVIX en cada inicio (o según el flujo de tu app).'),
                t('Prohibido revender, revender acceso o usar la API para spam, phishing o perfiles falsos.'),
                t('El uso está sujeto a los Términos y la Política de privacidad de TREVIX.'),
            ],
        ];
    }

    private static function encryptSecret(string $plain): string
    {
        $iv = random_bytes(16);
        $raw = openssl_encrypt($plain, self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, $iv);
        if ($raw === false) {
            throw new ActionError('No se pudo cifrar la clave API.', 500);
        }
        return base64_encode($iv . $raw);
    }

    private static function decryptSecret(string $enc): string
    {
        if ($enc === '') {
            return '';
        }
        $bin = base64_decode($enc, true);
        if ($bin === false || strlen($bin) < 17) {
            return '';
        }
        $plain = openssl_decrypt(substr($bin, 16), self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, substr($bin, 0, 16));
        return $plain === false ? '' : $plain;
    }

    private static function cryptoKey(): string
    {
        return hash('sha256', implode('|', [
            (string) Config::get('database.password', ''),
            (string) Config::get('app.url', ''),
            (string) Config::get('app.name', 'TREVIX'),
            'oauth-secret-v1',
        ]), true);
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
            'client_secret_enc'  => self::encryptSecret($secret),
            'status'             => 'pending',
        ]);
        $app = OAuthApp::find($id);
        if ($app === null) {
            $app = [
                'id' => $id, 'owner_id' => (int) $user['id'], 'name' => $name, 'description' => $description,
                'icon_path' => $iconPath, 'platform' => $platform, 'package_name' => $package, 'website_url' => $website,
                'redirect_uris' => implode("\n", $lines), 'client_id' => $clientId, 'status' => 'pending',
                'client_secret_enc' => self::encryptSecret($secret),
                'review_note' => null, 'created_at' => date('Y-m-d H:i:s'),
            ];
        }
        $presented = self::presentApp($app, true, true);
        if (empty($presented['client_secret'])) {
            $presented['client_secret'] = $secret;
            $presented['has_secret'] = true;
        }
        return [
            'message'       => t('Solicitud enviada. Cuando un administrador o moderador la apruebe, la API funcionará.'),
            'app'           => $presented,
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
            'items'   => array_map(static fn (array $a) => self::presentApp($a, true, false), $result['items']),
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
