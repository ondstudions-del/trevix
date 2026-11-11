<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Database;
use Trevix\Models\Conversation;
use Trevix\Models\Group;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/**
 * Grupos de mensajes. Quien lo crea es el dueño; los administradores (dueño incluido) cambian el nombre, la foto,
 * la portada, el estilo, la descripción, la visibilidad y los mensajes temporales, añaden y quitan participantes,
 * aceptan solicitudes y restablecen el enlace. Solo el dueño nombra administradores.
 * Para añadir a alguien se respeta su privacidad de mensajes y los bloqueos (igual que para escribirle).
 */
final class GroupService
{
    private static function action(int $uid, string $limit = 'group_action'): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit($limit, $key, $limit === 'group_create'
            ? 'Creaste muchos grupos hoy. Vuelve a intentarlo mañana.'
            : 'Hiciste demasiadas acciones en grupos. Espera un momento.');
        RateLimit::hit($limit, $key);
    }

    /** Grupo en el que participa $uid, con su rol. */
    public static function load(int $uid, int $groupId): array
    {
        $group = $groupId > 0 ? Group::find($groupId) : null;
        $role = $group !== null ? Group::role($groupId, $uid) : null;
        if ($group === null || $role === null) {
            throw new ActionError('Este grupo no existe o ya no participas en él.', 404);
        }
        return $group + ['viewer_role' => $role];
    }

    private static function manager(array $group): void
    {
        if (!Group::isManager($group['viewer_role'])) {
            throw new ActionError('Solo los administradores del grupo pueden hacer esto.', 403);
        }
    }

    private static function title(string $title): string
    {
        $max = (int) Config::get('app.chat.group_title_max', 80);
        $title = Guard::singleLine($title, 400) ?? '';
        if ($title === '') {
            throw ActionError::field('title', 'Ponle un nombre al grupo.');
        }
        if (mb_strlen($title) > $max || preg_match('/[<>\p{C}]/u', $title)) {
            throw ActionError::field('title', t('El nombre puede tener hasta {n} caracteres, sin símbolos especiales.', ['n' => $max]));
        }
        return $title;
    }

    private static function description(string $description): ?string
    {
        $max = (int) Config::get('app.chat.group_description_max', 500);
        $description = trim(Guard::cleanText($description));
        if (mb_strlen($description) > $max) {
            throw ActionError::field('description', t('La descripción puede tener hasta {n} caracteres.', ['n' => $max]));
        }
        return $description !== '' ? $description : null;
    }

    private static function visibility(string $visibility): string
    {
        if (!in_array($visibility, ['private', 'public'], true)) {
            throw ActionError::field('visibility', 'Elige si el grupo es público o privado.');
        }
        return $visibility;
    }

    /**
     * Personas que se pueden añadir: [ok => list<array>, failed => array<usuario, motivo>].
     *
     * @param list<string> $usernames
     */
    private static function candidates(int $uid, array $usernames, ?int $groupId): array
    {
        $usernames = array_values(array_unique(array_filter(array_map(
            static fn ($u) => mb_strtolower(trim(ltrim(trim((string) $u), '@'))),
            $usernames
        ))));
        $ok = [];
        $failed = [];
        foreach (array_slice($usernames, 0, 100) as $username) {
            $person = User::findByUsername($username);
            $reason = Conversation::cannotMessage($uid, $person, null);
            if ($reason === null && $groupId !== null && Group::role($groupId, (int) $person['id']) !== null) {
                $reason = t('@{username} ya está en el grupo.', ['username' => $username]);
            }
            if ($reason !== null) {
                $failed[$username] = $reason === t('No puedes enviarte mensajes a ti mismo.') ? t('Ya estás en el grupo.') : $reason;
                continue;
            }
            $ok[] = $person;
        }
        return ['ok' => $ok, 'failed' => $failed];
    }

    /**
     * Crea un grupo con las personas indicadas (las que no se pueden añadir se informan en «failed»).
     *
     * @param list<string> $usernames
     * @return array{id:int, failed: array<string, string>}
     */
    public static function create(array $user, string $title, string $description, string $visibility, array $usernames): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $title = self::title($title);
        $description = self::description($description);
        $visibility = self::visibility($visibility);
        $people = self::candidates($uid, $usernames, null);
        $max = (int) Config::get('app.chat.group_max_members', 256);
        if (count($people['ok']) + 1 > $max) {
            throw ActionError::field('members', t('Un grupo puede tener hasta {n} participantes.', ['n' => $max]));
        }
        if ($people['ok'] === [] && $usernames !== []) {
            throw ActionError::field('members', (string) reset($people['failed']));
        }
        self::action($uid, 'group_create');

        try {
            $avatar = ImageUpload::storeProfileImage('avatar', 'group_avatar');
        } catch (RuntimeException $e) {
            throw ActionError::field('avatar', $e->getMessage());
        }
        try {
            $id = Database::transaction(static function () use ($uid, $title, $description, $visibility, $avatar, $people): int {
                $id = Group::create($uid, $title, $description, $visibility, $avatar);
                Conversation::notice($id, $uid, 'group:create');
                foreach ($people['ok'] as $person) {
                    Group::addMember($id, (int) $person['id']);
                    Conversation::notice($id, $uid, 'group:add:' . (int) $person['id']);
                }
                return $id;
            });
        } catch (\Throwable $e) {
            ImageUpload::delete($avatar);
            throw $e;
        }
        return ['id' => $id, 'failed' => $people['failed']];
    }

    /**
     * Cambia los datos enviados: title, description, theme, visibility, disappear_seconds. Cada cambio deja su
     * aviso en el chat. Devuelve el texto de confirmación.
     */
    public static function update(int $uid, array $group, array $changes): string
    {
        self::manager($group);
        $groupId = (int) $group['id'];
        $fields = [];
        $notices = [];
        if (array_key_exists('title', $changes)) {
            $title = self::title((string) $changes['title']);
            if ($title !== $group['title']) {
                $fields['title'] = $title;
                $notices[] = 'group:title';
            }
        }
        if (array_key_exists('description', $changes)) {
            $description = self::description((string) ($changes['description'] ?? ''));
            if ($description !== $group['description']) {
                $fields['description'] = $description;
                $notices[] = 'group:description';
            }
        }
        if (array_key_exists('visibility', $changes)) {
            $visibility = self::visibility((string) $changes['visibility']);
            if ($visibility !== $group['visibility']) {
                $fields['visibility'] = $visibility;
                $notices[] = 'group:visibility:' . $visibility;
            }
        }
        $theme = null;
        if (array_key_exists('theme', $changes)) {
            $theme = (string) $changes['theme'];
            if (!isset(((array) Config::get('app.chat.themes', []))[$theme])) {
                throw ActionError::field('theme', 'Elige uno de los estilos disponibles.');
            }
        }
        $disappear = null;
        if (array_key_exists('disappear_seconds', $changes)) {
            $disappear = (int) $changes['disappear_seconds'];
            if (!array_key_exists($disappear, (array) Config::get('app.chat.disappear_options', []))) {
                throw ActionError::field('disappear_seconds', 'Elige una de las duraciones disponibles.');
            }
        }
        self::action($uid);
        Database::transaction(static function () use ($groupId, $uid, $fields, $notices): void {
            Group::update($groupId, $fields);
            foreach ($notices as $code) {
                Conversation::notice($groupId, $uid, $code);
            }
        });
        if ($theme !== null) {
            Conversation::setTheme($groupId, $uid, $theme);
        }
        if ($disappear !== null) {
            Conversation::setDisappear($groupId, $uid, $disappear);
        }
        return 'Guardaste los cambios del grupo.';
    }

    /** Foto («avatar») o portada («cover») del grupo; $remove la quita. */
    public static function image(int $uid, array $group, string $kind, bool $remove): string
    {
        self::manager($group);
        $column = $kind === 'cover' ? 'cover_path' : 'avatar_path';
        $old = $group[$column];
        $path = null;
        if (!$remove) {
            try {
                $path = ImageUpload::storeProfileImage($kind, $kind === 'cover' ? 'group_cover' : 'group_avatar');
            } catch (RuntimeException $e) {
                throw ActionError::field($kind, $e->getMessage());
            }
            if ($path === null) {
                throw ActionError::field($kind, t('Adjunta la imagen en el campo «{field}» (multipart/form-data).', ['field' => $kind]));
            }
        } elseif ($old === null) {
            return 'El grupo no tenía esa imagen.';
        }
        self::action($uid);
        Database::transaction(static function () use ($group, $column, $path, $uid, $kind): void {
            Group::update((int) $group['id'], [$column => $path]);
            Conversation::notice((int) $group['id'], $uid, 'group:' . ($kind === 'cover' ? 'cover' : 'avatar'));
        });
        ImageUpload::delete($old);
        return $remove ? 'Quitaste la imagen del grupo.' : 'Guardaste la imagen del grupo.';
    }

    /**
     * Añade personas (solo administradores).
     *
     * @param list<string> $usernames
     * @return array{added: list<string>, failed: array<string, string>}
     */
    public static function addMembers(int $uid, array $group, array $usernames): array
    {
        self::manager($group);
        $groupId = (int) $group['id'];
        $people = self::candidates($uid, $usernames, $groupId);
        if ($people['ok'] === []) {
            throw ActionError::field('members', $people['failed'] !== [] ? (string) reset($people['failed']) : 'Elige a quién añadir.');
        }
        $max = (int) Config::get('app.chat.group_max_members', 256);
        if (Group::memberCount($groupId) + count($people['ok']) > $max) {
            throw ActionError::field('members', t('Un grupo puede tener hasta {n} participantes.', ['n' => $max]));
        }
        self::action($uid);
        Database::transaction(static function () use ($groupId, $uid, $people): void {
            foreach ($people['ok'] as $person) {
                Group::addMember($groupId, (int) $person['id']);
                Conversation::notice($groupId, $uid, 'group:add:' . (int) $person['id']);
            }
        });
        return ['added' => array_map(static fn (array $p) => (string) $p['username'], $people['ok']), 'failed' => $people['failed']];
    }

    /** Quitar a alguien: los administradores quitan participantes; solo el dueño quita administradores. */
    public static function removeMember(int $uid, array $group, int $targetId): void
    {
        self::manager($group);
        $groupId = (int) $group['id'];
        if ($targetId === $uid) {
            throw new ActionError('Para irte del grupo usa «Salir del grupo».');
        }
        $role = Group::role($groupId, $targetId);
        if ($role === null) {
            throw new ActionError('Esa persona ya no está en el grupo.', 404);
        }
        if ($role === 'owner' || ($role === 'admin' && $group['viewer_role'] !== 'owner')) {
            throw new ActionError('Solo el creador del grupo puede quitar a un administrador.', 403);
        }
        self::action($uid);
        Database::transaction(static function () use ($groupId, $uid, $targetId): void {
            Group::removeMember($groupId, $targetId);
            Conversation::notice($groupId, $uid, 'group:remove:' . $targetId);
        });
    }

    /** Salir del grupo. Si sale el dueño, el grupo pasa a otra persona; si no queda nadie, se borra. */
    public static function leave(int $uid, array $group): void
    {
        $groupId = (int) $group['id'];
        self::action($uid);
        Database::transaction(static function () use ($groupId, $uid, $group): void {
            Conversation::notice($groupId, $uid, 'group:leave');
            Group::removeMember($groupId, $uid);
            if ($group['viewer_role'] === 'owner') {
                Group::promoteSuccessor($groupId);
            }
        });
        Group::deleteIfEmpty($groupId);
    }

    /** Nombrar ($admin = true) o quitar administrador (solo el dueño). */
    public static function setAdmin(int $uid, array $group, int $targetId, bool $admin): void
    {
        if ($group['viewer_role'] !== 'owner') {
            throw new ActionError('Solo el creador del grupo puede nombrar administradores.', 403);
        }
        $groupId = (int) $group['id'];
        $role = Group::role($groupId, $targetId);
        if ($role === null || $role === 'owner') {
            throw new ActionError('Esa persona ya no está en el grupo.', 404);
        }
        if (($role === 'admin') === $admin) {
            throw new ActionError($admin ? 'Ya es administrador.' : 'No es administrador.');
        }
        self::action($uid);
        Database::transaction(static function () use ($groupId, $uid, $targetId, $admin): void {
            Group::setRole($groupId, $targetId, $admin ? 'admin' : 'member');
            Conversation::notice($groupId, $uid, ($admin ? 'group:admin:' : 'group:unadmin:') . $targetId);
        });
    }

    /** Nuevo enlace de invitación (el anterior deja de funcionar). */
    public static function resetInvite(int $uid, array $group): string
    {
        self::manager($group);
        self::action($uid);
        $code = Group::newInviteCode();
        Database::transaction(static function () use ($group, $code, $uid): void {
            Group::update((int) $group['id'], ['invite_code' => $code]);
            Conversation::notice((int) $group['id'], $uid, 'group:link');
        });
        return $code;
    }

    /** Vista previa de un enlace de invitación para quien lo abre. */
    public static function preview(int $uid, string $code): array
    {
        $group = preg_match('/^[a-z0-9]{16}$/', $code) === 1 ? Group::findByInvite($code) : null;
        if ($group === null) {
            throw new ActionError('Este enlace de invitación no es válido o se restableció.', 404);
        }
        $groupId = (int) $group['id'];
        $state = match (true) {
            Group::role($groupId, $uid) !== null => 'member',
            Group::hasRequest($groupId, $uid)    => 'requested',
            default                              => 'none',
        };
        return ['group' => $group, 'members_count' => Group::memberCount($groupId), 'state' => $state];
    }

    /**
     * Entrar con el enlace: en los públicos directo; en los privados queda una solicitud para los administradores.
     *
     * @return array{state: string, conversation_id: int, message: string}
     */
    public static function join(array $user, string $code): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $preview = self::preview($uid, $code);
        $group = $preview['group'];
        $groupId = (int) $group['id'];
        if ($preview['state'] === 'member') {
            return ['state' => 'member', 'conversation_id' => $groupId, 'message' => 'Ya estás en este grupo.'];
        }
        if ($preview['state'] === 'requested') {
            return ['state' => 'requested', 'conversation_id' => $groupId, 'message' => 'Ya pediste unirte. Te avisaremos cuando te acepten.'];
        }
        if ($preview['members_count'] >= (int) Config::get('app.chat.group_max_members', 256)) {
            throw new ActionError('Este grupo está completo.');
        }
        self::action($uid);
        if ($group['visibility'] === 'public') {
            Database::transaction(static function () use ($groupId, $uid): void {
                Group::addMember($groupId, $uid);
                Conversation::notice($groupId, $uid, 'group:join');
            });
            return ['state' => 'member', 'conversation_id' => $groupId, 'message' => 'Te uniste al grupo.'];
        }
        Group::addRequest($groupId, $uid);
        return ['state' => 'requested', 'conversation_id' => $groupId, 'message' => 'Pediste unirte. Un administrador debe aceptarte.'];
    }

    /** Aceptar o rechazar una solicitud (administradores). */
    public static function resolveRequest(int $uid, array $group, int $targetId, bool $approve): string
    {
        self::manager($group);
        $groupId = (int) $group['id'];
        if (!Group::hasRequest($groupId, $targetId)) {
            throw new ActionError('Esta solicitud ya no está pendiente.', 404);
        }
        self::action($uid);
        if (!$approve) {
            Group::deleteRequest($groupId, $targetId);
            return 'Rechazaste la solicitud.';
        }
        $person = User::findActiveById($targetId);
        if ($person === null || User::blockedBetween($uid, $targetId)) {
            Group::deleteRequest($groupId, $targetId);
            throw new ActionError('Esta cuenta ya no está disponible.');
        }
        Database::transaction(static function () use ($groupId, $uid, $targetId): void {
            Group::addMember($groupId, $targetId);
            Conversation::notice($groupId, $uid, 'group:approve:' . $targetId);
        });
        return 'Aceptaste la solicitud.';
    }
}
