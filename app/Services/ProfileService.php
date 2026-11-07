<?php
declare(strict_types=1);

namespace Trevix\Services;

use PDOException;
use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Models\Follow;
use Trevix\Models\User;

/** Editar el perfil: datos públicos, foto, portada y privacidad (compartido por la web y la API). */
final class ProfileService
{
    /** @return array<string, string> código ISO => nombre del país */
    public static function countries(): array
    {
        return require APP_PATH . '/Data/countries.php';
    }

    /**
     * Guarda el perfil completo. Las imágenes nuevas llegan en $_FILES['avatar'] y $_FILES['cover'].
     *
     * Tipo de cuenta: si no llega account_type (o creator_category) se conserva el actual.
     *
     * @param array{display_name:string, username:string, bio:string, website:string, country:string,
     *              birth_date:string, is_private:bool, account_type?:string, creator_category?:string} $input
     * @return array{data: array, accepted: int}
     */
    public static function update(array $user, array $input, bool $removeAvatar, bool $removeCover): array
    {
        $id = (int) $user['id'];
        $accountType = trim((string) ($input['account_type'] ?? ($user['account_type'] ?? 'personal')));
        $data = [
            'display_name' => AccountRules::normalizeName((string) $input['display_name']),
            'username'     => mb_strtolower(trim((string) $input['username'])),
            'bio'          => trim(str_replace("\r\n", "\n", (string) $input['bio'])),
            'website'      => AccountRules::normalizeWebsite(trim((string) $input['website'])),
            'country'      => strtoupper(trim((string) $input['country'])),
            'birth_date'   => trim((string) $input['birth_date']),
            'is_private'   => !empty($input['is_private']) ? 1 : 0,
            'account_type' => $accountType,
            'creator_category' => $accountType === 'creator'
                ? trim((string) ($input['creator_category'] ?? ($user['creator_category'] ?? '')))
                : null,
        ];

        $countries = self::countries();
        $errors = array_filter([
            'account_type' => !isset(User::ACCOUNT_TYPES[$accountType]) ? 'Elige un tipo de cuenta válido.' : null,
            'creator_category' => $accountType === 'creator' && !isset(User::CREATOR_CATEGORIES[(string) $data['creator_category']])
                ? 'Elige la categoría de creador de contenido.' : null,
            'display_name' => AccountRules::displayName($data['display_name']),
            'username'     => $data['username'] !== $user['username'] ? AccountRules::username($data['username']) : null,
            'bio'          => AccountRules::bio($data['bio']),
            'website'      => AccountRules::website($data['website']),
            'country'      => $data['country'] !== '' && !isset($countries[$data['country']]) ? 'Elige un país de la lista.' : null,
            'birth_date'   => $data['birth_date'] !== '' ? AccountRules::birthDate($data['birth_date']) : null,
        ]);
        if (!isset($errors['username']) && User::usernameExists($data['username'], $id)) {
            $errors['username'] = 'Ese nombre de usuario ya está en uso.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $current = User::findBasicById($id) ?? [];
        $newImages = [];
        $avatar = $cover = null;
        $field = 'avatar';
        try {
            $avatar = ImageUpload::storeProfileImage('avatar', 'avatar');
            if ($avatar !== null) {
                $newImages[] = $avatar;
            }
            $field = 'cover';
            $cover = ImageUpload::storeProfileImage('cover', 'cover');
            if ($cover !== null) {
                $newImages[] = $cover;
            }
        } catch (RuntimeException $e) {
            array_walk($newImages, static fn (string $path) => ImageUpload::delete($path));
            throw ActionError::field($field, $e->getMessage());
        }

        $avatarPath = $avatar ?? ($removeAvatar ? null : ($current['avatar_path'] ?? null));
        $coverPath = $cover ?? ($removeCover ? null : ($current['cover_path'] ?? null));

        try {
            User::updateProfile($id, [
                'display_name' => $data['display_name'],
                'username'     => $data['username'],
                'bio'          => $data['bio'] !== '' ? $data['bio'] : null,
                'website'      => $data['website'] !== '' ? $data['website'] : null,
                'country'      => $data['country'] !== '' ? $data['country'] : null,
                'birth_date'   => $data['birth_date'] !== '' ? $data['birth_date'] : null,
                'is_private'   => $data['is_private'],
                'avatar_path'  => $avatarPath,
                'cover_path'   => $coverPath,
                'account_type' => $data['account_type'],
                'creator_category' => $data['creator_category'],
            ]);
        } catch (PDOException $e) {
            array_walk($newImages, static fn (string $path) => ImageUpload::delete($path));
            if ($e->getCode() !== '23000') {
                throw $e;
            }
            throw ActionError::field('username', 'Ese nombre de usuario ya está en uso.');
        }

        if (($current['avatar_path'] ?? null) !== $avatarPath) {
            ImageUpload::delete($current['avatar_path'] ?? null);
        }
        if (($current['cover_path'] ?? null) !== $coverPath) {
            ImageUpload::delete($current['cover_path'] ?? null);
        }

        $accepted = !empty($user['is_private']) && $data['is_private'] === 0 ? Follow::acceptAll($id) : 0;
        return ['data' => $data, 'accepted' => $accepted];
    }
}
