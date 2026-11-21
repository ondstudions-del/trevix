<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Models\Follow;
use Trevix\Models\Notification;
use Trevix\Models\ProfilePhoto;
use Trevix\Models\User;

final class ProfilePhotoService
{
    private static function kind(string $raw): string
    {
        $k = strtolower(trim($raw));
        if (!in_array($k, ProfilePhoto::KINDS, true)) {
            throw new ActionError('Tipo de foto no válido.', 422);
        }
        return $k;
    }

    private static function pathColumn(string $kind): string
    {
        return $kind === 'cover' ? 'cover_path' : 'avatar_path';
    }

    private static function prefix(string $kind): string
    {
        return $kind === 'cover' ? 'cover' : 'avatar';
    }

    public static function ownerHasPhoto(array $user, string $kind): bool
    {
        return trim((string) ($user[self::pathColumn($kind)] ?? '')) !== '';
    }

    /** @return array{can_view: bool, can_interact: bool} */
    public static function access(array $owner, ?array $viewer, string $kind): array
    {
        $ownerId = (int) $owner['id'];
        if (!$viewer) {
            $p = (string) ($owner[self::prefix($kind) . '_privacy'] ?? 'public');
            return ['can_view' => $p === 'public' && self::ownerHasPhoto($owner, $kind), 'can_interact' => false];
        }
        $vid = (int) $viewer['id'];
        if ($vid === $ownerId) {
            $has = self::ownerHasPhoto($owner, $kind);
            return ['can_view' => $has, 'can_interact' => $has];
        }
        if (!self::ownerHasPhoto($owner, $kind)) {
            return ['can_view' => false, 'can_interact' => false];
        }
        $privacy = (string) ($owner[self::prefix($kind) . '_privacy'] ?? 'public');
        if ($privacy === 'only_me') {
            return ['can_view' => false, 'can_interact' => false];
        }
        if ($privacy === 'followers') {
            $rel = Follow::relations($vid, [$ownerId])[$ownerId] ?? ['following' => false];
            if (empty($rel['following'])) {
                return ['can_view' => false, 'can_interact' => false];
            }
        }
        return ['can_view' => true, 'can_interact' => true];
    }

    /** @return array<string, mixed> */
    public static function present(array $owner, ?array $viewer, string $kind): array
    {
        $kind = self::kind($kind);
        $access = self::access($owner, $viewer, $kind);
        $ownerId = (int) $owner['id'];
        $vid = $viewer !== null ? (int) $viewer['id'] : 0;
        $pfx = self::prefix($kind);
        return [
            'kind'           => $kind,
            'url'            => $access['can_view'] ? \Trevix\Api\Present::file($owner[self::pathColumn($kind)] ?? null) : null,
            'caption'        => $access['can_view'] || ($viewer !== null && $vid === $ownerId)
                ? (string) ($owner[$pfx . '_caption'] ?? '') : '',
            'alt_text'       => $access['can_view'] || ($viewer !== null && $vid === $ownerId)
                ? (string) ($owner[$pfx . '_alt'] ?? '') : '',
            'privacy'        => (string) ($owner[$pfx . '_privacy'] ?? 'public'),
            'notify_muted'   => !empty($owner[$pfx . '_notify_muted']),
            'updated_at'     => \Trevix\Api\Present::date($owner[$pfx . '_updated_at'] ?? null),
            'likes_count'    => $access['can_view'] ? ProfilePhoto::likesCount($ownerId, $kind) : 0,
            'comments_count' => $access['can_view'] ? ProfilePhoto::commentsCount($ownerId, $kind) : 0,
            'liked'          => $vid > 0 && $access['can_view'] ? ProfilePhoto::liked($ownerId, $kind, $vid) : false,
            'can_like'       => $access['can_interact'],
            'can_comment'    => $access['can_interact'],
        ];
    }

    /** @param array{caption?: string, alt_text?: string, privacy?: string, notify_muted?: bool} $input */
    public static function updateMeta(array $user, string $kind, array $input): array
    {
        $kind = self::kind($kind);
        if (!self::ownerHasPhoto($user, $kind)) {
            throw new DomainException('Sube una foto antes de editar sus datos.');
        }
        $pfx = self::prefix($kind);
        $id = (int) $user['id'];
        $fields = [];
        if (array_key_exists('caption', $input)) {
            $caption = trim((string) $input['caption']);
            if (mb_strlen($caption) > 500) {
                throw new DomainException('El pie de foto es demasiado largo (máximo 500 caracteres).');
            }
            $fields[$pfx . '_caption'] = $caption === '' ? null : $caption;
        }
        if (array_key_exists('alt_text', $input)) {
            $alt = trim((string) $input['alt_text']);
            if (mb_strlen($alt) > 300) {
                throw new DomainException('El texto alternativo es demasiado largo (máximo 300 caracteres).');
            }
            $fields[$pfx . '_alt'] = $alt === '' ? null : $alt;
        }
        if (array_key_exists('privacy', $input)) {
            $p = strtolower(trim((string) $input['privacy']));
            if (!in_array($p, ProfilePhoto::PRIVACY, true)) {
                throw new DomainException('Elige una privacidad válida.');
            }
            $fields[$pfx . '_privacy'] = $p;
        }
        if (array_key_exists('notify_muted', $input)) {
            $fields[$pfx . '_notify_muted'] = !empty($input['notify_muted']) ? 1 : 0;
        }
        if ($fields === []) {
            throw new DomainException('No hay cambios que guardar.');
        }
        $fields[$pfx . '_updated_at'] = date('Y-m-d H:i:s');
        ProfilePhoto::updateUser($id, $fields);
        $fresh = User::findActiveById($id);
        return self::present($fresh ?? $user, $user, $kind);
    }

    public static function touchUpdatedAt(int $userId, string $kind): void
    {
        $kind = self::kind($kind);
        $pfx = self::prefix($kind);
        ProfilePhoto::updateUser($userId, [$pfx . '_updated_at' => date('Y-m-d H:i:s')]);
    }

    public static function clearMeta(int $userId, string $kind): void
    {
        $kind = self::kind($kind);
        $pfx = self::prefix($kind);
        ProfilePhoto::updateUser($userId, [
            $pfx . '_caption'      => null,
            $pfx . '_alt'          => null,
            $pfx . '_privacy'      => 'public',
            $pfx . '_notify_muted' => 0,
            $pfx . '_updated_at'   => null,
        ]);
        ProfilePhoto::clearInteractions($userId, $kind);
    }

    public static function toggleLike(array $viewer, int $ownerId, string $kind, bool $on): array
    {
        $kind = self::kind($kind);
        $owner = User::findActiveById($ownerId);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, $kind);
        if (!$access['can_interact']) {
            throw new ActionError('No puedes dar «Me gusta» a esta foto.', 403);
        }
        if ($on) {
            if (ProfilePhoto::like($ownerId, $kind, (int) $viewer['id'])) {
                if (empty($owner[self::prefix($kind) . '_notify_muted'])) {
                    Notification::notifyProfilePhoto($ownerId, (int) $viewer['id'], 'profile_photo_like', $kind);
                }
            }
        } else {
            ProfilePhoto::unlike($ownerId, $kind, (int) $viewer['id']);
        }
        return [
            'liked'       => ProfilePhoto::liked($ownerId, $kind, (int) $viewer['id']),
            'likes_count' => ProfilePhoto::likesCount($ownerId, $kind),
            'can_like'    => true,
            'can_comment' => $access['can_interact'],
        ];
    }

    /** @return list<array> */
    public static function listComments(array $viewer, int $ownerId, string $kind, int $beforeId = 0): array
    {
        $kind = self::kind($kind);
        $owner = User::findActiveById($ownerId);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, $kind);
        if (!$access['can_view']) {
            throw new ActionError('No puedes ver los comentarios de esta foto.', 403);
        }
        return ProfilePhoto::threaded($ownerId, $kind, (int) $viewer['id'], $beforeId, 30);
    }

    /**
     * @param array{path:string,width:int,height:int}|null $media
     * @return array shaped comment
     */
    public static function comment(
        array $viewer,
        int $ownerId,
        string $kind,
        string $body,
        int $parentParam = 0,
        string $gifId = '',
        string $gifKind = 'gif',
        ?array $media = null
    ): array {
        $kind = self::kind($kind);
        $body = trim($body);
        if ($body === '' && trim($gifId) === '' && $media === null) {
            throw ActionError::field('body', 'Escribe un comentario, elige un GIF o adjunta una foto.');
        }
        if (mb_strlen($body) > 1000) {
            throw ActionError::field('body', 'Escribe un comentario de máximo 1000 caracteres.');
        }
        $owner = User::findActiveById($ownerId);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, $kind);
        if (!$access['can_interact']) {
            throw new ActionError('No puedes comentar esta foto.', 403);
        }

        $parentId = null;
        if ($parentParam > 0) {
            $parent = ProfilePhoto::findComment($parentParam);
            if ($parent === null
                || (int) $parent['owner_id'] !== $ownerId
                || (string) $parent['kind'] !== $kind) {
                throw new ActionError('El comentario al que respondes ya no existe.', 404);
            }
            $parentId = $parent['parent_id'] !== null ? (int) $parent['parent_id'] : (int) $parent['id'];
        }

        $gif = Giphy::resolve($gifId, $gifKind);
        $cid = ProfilePhoto::addComment($ownerId, $kind, (int) $viewer['id'], $body, $parentId, $gif, $media);

        if (empty($owner[self::prefix($kind) . '_notify_muted'])) {
            try {
                Notification::notifyProfilePhoto($ownerId, (int) $viewer['id'], 'profile_photo_comment', $kind);
            } catch (\Throwable) {
            }
        }

        $row = ProfilePhoto::findComment($cid);
        if ($row === null) {
            throw new ActionError('No se pudo publicar el comentario.', 500);
        }
        $shaped = ProfilePhoto::threaded($ownerId, $kind, (int) $viewer['id'], $cid + 1, 1);
        // Si es respuesta, devolver solo esa respuesta shaped
        if ($parentId !== null) {
            $full = ProfilePhoto::findComment($cid);
            return self::presentCommentRow($full ?? $row, (int) $viewer['id'], $ownerId);
        }
        foreach ($shaped as $item) {
            if ((int) $item['id'] === $cid) {
                return $item;
            }
        }
        return self::presentCommentRow($row, (int) $viewer['id'], $ownerId);
    }

    /** @return array{reaction:?string,likes:int,dislikes:int} */
    public static function reactComment(array $viewer, int $commentId, ?string $value): array
    {
        $row = ProfilePhoto::findComment($commentId);
        if ($row === null) {
            throw new ActionError('Este comentario ya no está disponible.', 404);
        }
        $owner = User::findActiveById((int) $row['owner_id']);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, (string) $row['kind']);
        if (!$access['can_view']) {
            throw new ActionError('No puedes reaccionar a este comentario.', 403);
        }
        if ($value !== null && $value !== 'like' && $value !== 'dislike') {
            throw ActionError::field('value', 'Elige me gusta o no me gusta.');
        }
        return ProfilePhoto::setReaction($commentId, (int) $viewer['id'], $value);
    }

    public static function deleteComment(array $viewer, int $commentId): void
    {
        $row = ProfilePhoto::findComment($commentId);
        if ($row === null) {
            throw new ActionError('Este comentario ya no está disponible.', 404);
        }
        $uid = (int) $viewer['id'];
        $ownerId = (int) $row['owner_id'];
        $authorId = (int) $row['user_id'];
        if ($uid !== $authorId && $uid !== $ownerId) {
            throw new ActionError('No puedes eliminar este comentario.', 403);
        }
        ProfilePhoto::deleteComment($commentId);
    }

    private static function presentCommentRow(array $row, int $viewerId, int $ownerId): array
    {
        // Reusa threaded shape de un solo nodo.
        $stats = ProfilePhoto::reactionStats((int) $row['id'], $viewerId);
        return [
            'id'              => (int) $row['id'],
            'owner_id'        => (int) $row['owner_id'],
            'kind'            => (string) $row['kind'],
            'user_id'         => (int) $row['user_id'],
            'parent_id'       => $row['parent_id'] !== null ? (int) $row['parent_id'] : null,
            'body'            => (string) ($row['body'] ?? ''),
            'gif'             => Giphy::fromRow($row),
            'media'           => !empty($row['media_path'])
                ? ['path' => (string) $row['media_path'], 'width' => (int) ($row['media_width'] ?? 0), 'height' => (int) ($row['media_height'] ?? 0)]
                : null,
            'likes_count'     => $stats['likes'],
            'dislikes_count'  => $stats['dislikes'],
            'viewer_reaction' => $stats['reaction'],
            'replies_count'   => 0,
            'replies'         => [],
            'created_at'      => (string) ($row['created_at'] ?? ''),
            'user'            => [
                'id'               => (int) $row['user_id'],
                'username'         => (string) $row['username'],
                'display_name'     => (string) $row['display_name'],
                'avatar_path'      => $row['avatar_path'] ?? null,
                'account_type'     => $row['account_type'] ?? 'personal',
                'creator_category' => $row['creator_category'] ?? null,
                'is_verified'      => !empty($row['is_verified']),
            ],
        ];
    }
}
