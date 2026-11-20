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
            return ['can_view' => self::ownerHasPhoto($owner, $kind), 'can_interact' => true];
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
        $out = [
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
            'can_like'       => $access['can_interact'] && $vid !== $ownerId,
            'can_comment'    => $access['can_interact'],
        ];
        return $out;
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
            $pfx . '_caption'       => null,
            $pfx . '_alt'           => null,
            $pfx . '_privacy'       => 'public',
            $pfx . '_notify_muted'  => 0,
            $pfx . '_updated_at'    => null,
        ]);
        ProfilePhoto::execute('DELETE FROM profile_photo_likes WHERE owner_id = ? AND kind = ?', [$userId, $kind]);
        ProfilePhoto::execute('DELETE FROM profile_photo_comments WHERE owner_id = ? AND kind = ?', [$userId, $kind]);
    }

    public static function toggleLike(array $viewer, int $ownerId, string $kind, bool $on): array
    {
        $kind = self::kind($kind);
        $owner = User::findBasicById($ownerId);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, $kind);
        if (!$access['can_interact'] || (int) $viewer['id'] === $ownerId) {
            throw new ActionError('No puedes dar «Me gusta» a esta foto.', 403);
        }
        if ($on) {
            if (ProfilePhoto::like($ownerId, $kind, (int) $viewer['id'])) {
                if (empty($owner[self::prefix($kind) . '_notify_muted'])) {
                    Notification::notify($ownerId, (int) $viewer['id'], 'like', null, null);
                }
            }
        } else {
            ProfilePhoto::unlike($ownerId, $kind, (int) $viewer['id']);
        }
        return [
            'liked'        => ProfilePhoto::liked($ownerId, $kind, (int) $viewer['id']),
            'likes_count'  => ProfilePhoto::likesCount($ownerId, $kind),
        ];
    }

    public static function comment(array $viewer, int $ownerId, string $kind, string $body): array
    {
        $kind = self::kind($kind);
        $body = trim($body);
        if (mb_strlen($body) < 1 || mb_strlen($body) > 1000) {
            throw ActionError::field('body', 'Escribe un comentario de 1 a 1000 caracteres.');
        }
        $owner = User::findBasicById($ownerId);
        if ($owner === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $access = self::access($owner, $viewer, $kind);
        if (!$access['can_comment']) {
            throw new ActionError('No puedes comentar esta foto.', 403);
        }
        $cid = ProfilePhoto::addComment($ownerId, $kind, (int) $viewer['id'], $body);
        if (empty($owner[self::prefix($kind) . '_notify_muted'])) {
            Notification::notify($ownerId, (int) $viewer['id'], 'comment', null, $cid);
        }
        $rows = ProfilePhoto::comments($ownerId, $kind, $cid + 1, 1);
        $row = $rows[0] ?? null;
        return $row !== null ? \Trevix\Api\Present::profilePhotoComment($row) : ['id' => $cid];
    }
}