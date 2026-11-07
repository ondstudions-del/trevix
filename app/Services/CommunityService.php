<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Community;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/** Crear comunidades, unirse, salir, moderar miembros y administrarlas (compartido por la web y la API). */
final class CommunityService
{
    /** Permisos de quien mira sobre la comunidad (según la membresía cargada con Community::find). */
    public static function access(array $community): array
    {
        $membership = $community['membership'];
        $active = ($membership['status'] ?? '') === 'active';
        $role = $active ? $membership['role'] : null;
        return [
            'member'  => $active,
            'owner'   => $role === 'owner',
            'manager' => in_array($role, ['owner', 'moderator'], true),
            'banned'  => ($membership['status'] ?? '') === 'banned',
            'pending' => ($membership['status'] ?? '') === 'pending',
            'canView' => $community['visibility'] === 'public' || $active,
            'canPost' => $active,
        ];
    }

    /** Los moderadores no pueden quitar publicaciones del administrador. */
    public static function canModeratePost(array $community, array $access, int $authorId): bool
    {
        return $access['manager'] && ($access['owner'] || $authorId !== $community['owner_id']);
    }

    /** @return array{id:int, slug:string} */
    public static function create(array $user, string $name, string $description, string $category, string $visibility): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);

        $name = self::singleLine($name);
        $description = Guard::cleanText($description);
        $visibility = $visibility !== '' ? $visibility : 'public';
        $errors = self::validateInfo($name, $description, $category);
        if (!isset(Community::VISIBILITIES[$visibility])) {
            $errors['visibility'] = 'Elige si la comunidad será pública o privada.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $rateKey = 'user:' . $uid;
        if (RateLimit::tooManyAttempts('community_create', $rateKey)) {
            $seconds = RateLimit::availableIn('community_create', $rateKey);
            $message = 'Creaste varias comunidades hoy. Podrás crear otra en ' . max(1, (int) ceil($seconds / 3600)) . ' h.';
            throw new ActionError($message, 429, ['name' => $message], max(1, $seconds));
        }
        RateLimit::hit('community_create', $rateKey);

        $created = Community::create($uid, $name, $description !== '' ? $description : null, $category, $visibility);
        return ['id' => (int) $created['id'], 'slug' => (string) $created['slug']];
    }

    /** Límite de acciones por persona y comunidad activa con la membresía de quien actúa. */
    public static function load(int $uid, int $communityId): array
    {
        Guard::rateLimit('community_action', 'user:' . $uid, 'Vas demasiado rápido. Espera un momento.');
        RateLimit::hit('community_action', 'user:' . $uid);
        $community = $communityId > 0 ? Community::find($communityId, $uid) : null;
        if ($community === null) {
            throw new ActionError('Esta comunidad ya no está disponible.', 404);
        }
        return $community;
    }

    public static function join(int $uid, array $community): string
    {
        $state = $community['membership']['status'] ?? null;
        if ($state === 'banned') {
            throw new ActionError('No puedes unirte a esta comunidad.', 403);
        }
        $result = $state === null ? Community::join($community['id'], $uid, $community['visibility'] === 'private') : null;
        if ($result === 'pending') {
            foreach (Community::managerIds($community['id']) as $managerId) {
                Notification::notify($managerId, $uid, 'community_request', null, null, $community['id']);
            }
        }
        return ($result ?? $state) === 'pending'
            ? 'Enviaste tu solicitud. Te avisaremos cuando la acepten.'
            : 'Ahora eres miembro de ' . $community['name'] . '.';
    }

    public static function leave(int $uid, array $community): string
    {
        if (($community['membership']['role'] ?? '') === 'owner') {
            throw new ActionError('Eres el administrador: transfiere la comunidad a otro miembro antes de salir.');
        }
        $previous = Community::leave($community['id'], $uid);
        if ($previous === 'pending') {
            Notification::removeForCommunity($community['id'], $uid, 'community_request');
        }
        return $previous === 'pending' ? 'Cancelaste tu solicitud.' : 'Saliste de ' . $community['name'] . '.';
    }

    public static function resolveRequest(int $uid, array $community, int $targetId, bool $approve): string
    {
        self::requireRole(self::access($community)['manager']);
        $done = $approve ? Community::approve($community['id'], $targetId) : Community::reject($community['id'], $targetId);
        if (!$done) {
            throw new ActionError('Esa solicitud ya no está pendiente.', 409);
        }
        Notification::removeForCommunity($community['id'], $targetId, 'community_request');
        if ($approve) {
            Notification::notify($targetId, $uid, 'community_accepted', null, null, $community['id']);
        }
        return $approve ? 'Aceptaste la solicitud.' : 'Rechazaste la solicitud.';
    }

    public static function ban(int $uid, array $community, int $targetId): string
    {
        $access = self::access($community);
        self::requireRole($access['manager']);
        $target = Community::membership($community['id'], $targetId);
        if ($targetId === $uid || $target === null || $target['role'] === 'owner') {
            throw new ActionError('No puedes vetar a esta persona.', 403);
        }
        if ($target['role'] === 'moderator' && !$access['owner']) {
            throw new ActionError('Solo el administrador puede vetar a un moderador.', 403);
        }
        if (!Community::ban($community['id'], $targetId)) {
            throw new ActionError('Esa persona ya estaba vetada.', 409);
        }
        if ($target['status'] === 'pending') {
            Notification::removeForCommunity($community['id'], $targetId, 'community_request');
        }
        return 'La persona fue vetada y ya no puede participar en la comunidad.';
    }

    public static function unban(array $community, int $targetId): string
    {
        self::requireRole(self::access($community)['manager']);
        if (!Community::unban($community['id'], $targetId)) {
            throw new ActionError('Esa persona no estaba vetada.', 409);
        }
        return 'Levantaste el veto. Esa persona puede volver a unirse.';
    }

    public static function setRole(array $community, int $targetId, bool $promote): string
    {
        self::requireRole(self::access($community)['owner']);
        if (!Community::setRole($community['id'], $targetId, $promote ? 'moderator' : 'member')) {
            throw new ActionError('Solo se puede cambiar el rol de miembros activos.', 409);
        }
        return $promote ? 'Nombraste a un nuevo moderador.' : 'Esa persona ya no es moderadora.';
    }

    public static function removePost(array $community, int $postId): string
    {
        $access = self::access($community);
        self::requireRole($access['manager']);
        $post = $postId > 0 ? Post::findRaw($postId) : null;
        if ($post === null || (int) $post['community_id'] !== $community['id']) {
            throw new ActionError('Esa publicación ya no está en la comunidad.', 404);
        }
        if (!self::canModeratePost($community, $access, (int) $post['user_id'])) {
            throw new ActionError('No puedes quitar esta publicación.', 403);
        }
        Community::removePost($community, (int) $post['id']);
        return 'Quitaste la publicación de la comunidad.';
    }

    /**
     * Datos, imágenes ($_FILES['avatar'] y $_FILES['cover']) y visibilidad (solo el administrador).
     *
     * @param array{name:string, description:string, category:string, visibility:string} $info
     */
    public static function update(int $uid, array $community, array $info, bool $removeAvatar, bool $removeCover): string
    {
        self::requireRole(self::access($community)['owner']);
        $name = self::singleLine((string) $info['name']);
        $description = Guard::cleanText((string) $info['description']);
        $category = (string) $info['category'];
        $visibility = (string) $info['visibility'];

        $errors = self::validateInfo($name, $description, $category);
        if (!isset(Community::VISIBILITIES[$visibility])) {
            $errors['visibility'] = 'Elige si la comunidad será pública o privada.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $images = [];
        foreach (['avatar', 'cover'] as $kind) {
            try {
                $images[$kind] = ImageUpload::storeProfileImage($kind, 'community_' . $kind);
            } catch (RuntimeException $e) {
                foreach ($images as $path) {
                    ImageUpload::delete($path);
                }
                throw ActionError::field($kind, $e->getMessage());
            }
        }

        Community::update($community['id'], $name, $description !== '' ? $description : null, $category);
        $remove = ['avatar' => $removeAvatar, 'cover' => $removeCover];
        foreach (['avatar', 'cover'] as $kind) {
            if ($images[$kind] !== null) {
                Community::setImage($community, $kind, $images[$kind]);
            } elseif ($remove[$kind]) {
                Community::setImage($community, $kind, null);
            }
        }

        if ($visibility === $community['visibility']) {
            return 'Guardaste los cambios de la comunidad.';
        }
        $accepted = Community::setVisibility($community['id'], $visibility);
        foreach ($accepted as $acceptedId) {
            Notification::removeForCommunity($community['id'], $acceptedId, 'community_request');
            Notification::notify($acceptedId, $uid, 'community_accepted', null, null, $community['id']);
        }
        return $visibility === 'public'
            ? 'La comunidad ahora es pública' . ($accepted !== [] ? ' y se aceptaron ' . count($accepted) . ' solicitudes pendientes.' : '.')
            : 'La comunidad ahora es privada: solo sus miembros verán las publicaciones.';
    }

    /** Pasa la administración a otro miembro activo. Devuelve la cuenta que la recibe. */
    public static function transfer(array $user, array $community, string $username, string $password, string $usernameField, string $passwordField): array
    {
        self::requireRole(self::access($community)['owner']);
        SettingsService::confirmPassword($user, $password, $passwordField);

        $username = ltrim(mb_strtolower(trim($username)), '@');
        $target = $username !== '' ? User::findByUsername($username) : null;
        $membership = $target !== null ? Community::membership($community['id'], (int) $target['id']) : null;
        if ($target === null || $target['status'] !== 'active' || ($membership['status'] ?? '') !== 'active' || (int) $target['id'] === (int) $user['id']) {
            throw ActionError::field($usernameField, 'Escribe el usuario de un miembro activo de la comunidad.');
        }
        if (!Community::transfer($community['id'], (int) $user['id'], (int) $target['id'])) {
            throw ActionError::field($usernameField, 'No se pudo transferir la comunidad a esa persona.', 409);
        }
        return $target;
    }

    public static function delete(array $user, array $community, string $confirm, string $password, string $confirmField, string $passwordField): void
    {
        self::requireRole(self::access($community)['owner']);
        if (!hash_equals($community['slug'], trim($confirm))) {
            throw ActionError::field($confirmField, 'Escribe exactamente «' . $community['slug'] . '» para confirmar.');
        }
        SettingsService::confirmPassword($user, $password, $passwordField);
        Community::delete($community);
    }

    public static function validateInfo(string $name, string $description, string $category): array
    {
        $limits = Config::get('app.limits');
        $errors = [];
        $length = mb_strlen($name);
        if ($length < 3 || $length > (int) $limits['community_name']) {
            $errors['name'] = 'El nombre debe tener entre 3 y ' . (int) $limits['community_name'] . ' caracteres.';
        } elseif (!preg_match('/[\p{L}\p{N}]/u', $name)) {
            $errors['name'] = 'El nombre debe incluir letras o números.';
        }
        if (mb_strlen($description) > (int) $limits['community_description']) {
            $errors['description'] = 'La descripción no puede superar los ' . (int) $limits['community_description'] . ' caracteres.';
        }
        if (!in_array($category, Community::CATEGORIES, true)) {
            $errors['category'] = 'Elige una categoría de la lista.';
        }
        return $errors;
    }

    private static function singleLine(string $text): string
    {
        return trim((string) preg_replace('/\s+/u', ' ', Guard::cleanText($text)));
    }

    private static function requireRole(bool $allowed): void
    {
        if (!$allowed) {
            throw new ActionError('No tienes permiso para hacer esto en la comunidad.', 403);
        }
    }
}
