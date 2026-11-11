<?php

use Trevix\Core\Config;
use Trevix\Models\User;

/**
 * @var array|null $viewer
 * @var array      $countries
 * @var array      $errors
 * @var array      $old
 * @var bool       $canEdit
 */
$viewer = $viewer ?? [];
$limits = Config::get('app.limits');
$imageMimes = implode(',', Config::get('app.uploads.image.mimes'));
$maxImageBytes = (int) Config::get('app.uploads.profile.max_bytes');
$maxImageMb = (int) round($maxImageBytes / 1048576);
$cover = !empty($viewer['cover_path'])
    ? url($viewer['cover_path'])
    : (!empty($viewer['cover_art']) ? url('assets/img/demo/' . $viewer['cover_art'] . '.svg') : null);
$value = static fn (string $key): string => (string) ($old[$key] ?? $viewer[$key] ?? '');
$countryValue = $value('country');
$countryCode = isset($countries[$countryValue]) ? $countryValue : (array_search($countryValue, $countries, true) ?: '');
$isPrivate = array_key_exists('is_private', $old) ? (bool) $old['is_private'] : !empty($viewer['is_private']);
$accountType = $value('account_type') ?: 'personal';
$creatorCategory = $value('creator_category');
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(profile_url($viewer)) ?>" aria-label="<?= e(t('Volver al perfil')) ?>"><?= icon('arrow-left') ?></a>
        <div>
            <h1 class="page-header__title page-header__title--visible"><?= e(t('Editar perfil')) ?></h1>
            <p class="page-header__subtitle"><?= e(t('Así te verán las demás personas en TREVIX.')) ?></p>
        </div>
    </div>
</header>

<?php if (isset($errors['avatar']) || isset($errors['cover'])): ?>
    <div class="alert alert--error" role="alert">
        <?= icon('triangle-alert') ?>
        <p><?= e(t($errors['avatar'] ?? $errors['cover'])) ?></p>
    </div>
<?php endif; ?>

<form class="form edit-profile" method="post" action="<?= e(url('edit-profile.php')) ?>" enctype="multipart/form-data" novalidate data-validate>
    <?= csrf_field() ?>

    <div class="edit-profile__media">
        <div class="edit-profile__cover">
            <img src="<?= e($cover ?? 'data:,') ?>" alt="" data-preview="cover" <?= $cover ? '' : 'hidden' ?>>
            <label class="btn btn--glass btn--sm edit-profile__upload">
                <?= icon('camera') ?> <?= e(t('Cambiar portada')) ?>
                <input class="sr-only" type="file" name="cover" accept="<?= e($imageMimes) ?>" data-image-preview="cover" data-max-bytes="<?= (int) $maxImageBytes ?>">
            </label>
        </div>
        <div class="edit-profile__avatar">
            <span data-preview-fallback="avatar"><?= avatar($viewer, 'xl') ?></span>
            <img class="avatar avatar--xl" src="data:," alt="" data-preview="avatar" hidden>
            <label class="edit-profile__avatar-btn" aria-label="<?= e(t('Cambiar foto de perfil')) ?>">
                <?= icon('camera') ?>
                <input class="sr-only" type="file" name="avatar" accept="<?= e($imageMimes) ?>" data-image-preview="avatar" data-max-bytes="<?= (int) $maxImageBytes ?>">
            </label>
        </div>
    </div>

    <div class="card form-card">
        <p class="field__hint"><?= e(t('Foto de perfil y portada: JPG, PNG, WEBP o GIF de hasta {n} MB. Se recortan al centro (cuadrada la foto, 3:1 la portada).', ['n' => $maxImageMb])) ?></p>
        <?php if (!empty($viewer['avatar_path']) || !empty($viewer['cover_path'])): ?>
            <div class="edit-profile__remove">
                <?php if (!empty($viewer['avatar_path'])): ?>
                    <label class="checkbox">
                        <input type="checkbox" name="remove_avatar" value="1">
                        <span class="checkbox__box"><?= icon('check') ?></span>
                        <span><?= e(t('Quitar foto de perfil')) ?></span>
                    </label>
                <?php endif; ?>
                <?php if (!empty($viewer['cover_path'])): ?>
                    <label class="checkbox">
                        <input type="checkbox" name="remove_cover" value="1">
                        <span class="checkbox__box"><?= icon('check') ?></span>
                        <span><?= e(t('Quitar portada')) ?></span>
                    </label>
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="ep-name"><?= e(t('Nombre')) ?></label>
                <input class="input" id="ep-name" name="display_name" type="text" minlength="2" maxlength="<?= (int) $limits['display_name'] ?>" required
                    data-rule="name" value="<?= e($value('display_name')) ?>" data-char-count="#ep-name-count"<?= invalid_attrs($errors, 'display_name', 'ep-name') ?>>
                <?= field_error($errors, 'display_name', 'ep-name') ?>
                <p class="field__hint"><span id="ep-name-count"></span></p>
            </div>
            <div class="field">
                <label class="field__label" for="ep-username"><?= e(t('Nombre de usuario')) ?></label>
                <div class="input-wrap input-wrap--prefix">
                    <span class="input-wrap__prefix">@</span>
                    <input class="input" id="ep-username" name="username" type="text" minlength="3" maxlength="30" pattern="[a-z0-9_.]{3,30}" required
                        data-rule="username" value="<?= e($value('username')) ?>" spellcheck="false" autocapitalize="none" data-username-input<?= invalid_attrs($errors, 'username', 'ep-username') ?>>
                </div>
                <?= field_error($errors, 'username', 'ep-username') ?>
                <p class="field__hint"><?= e(t('Debe ser único. Solo minúsculas, números, punto y guion bajo.')) ?></p>
            </div>
        </div>

        <div class="field">
            <label class="field__label" for="ep-bio"><?= e(t('Biografía')) ?></label>
            <textarea class="input textarea" id="ep-bio" name="bio" rows="3" maxlength="<?= (int) $limits['bio'] ?>" data-autosize
                data-char-count="#ep-bio-count"<?= invalid_attrs($errors, 'bio', 'ep-bio') ?>><?= e($value('bio')) ?></textarea>
            <?= field_error($errors, 'bio', 'ep-bio') ?>
            <p class="field__hint"><span id="ep-bio-count"></span></p>
        </div>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="ep-website"><?= e(t('Sitio web')) ?></label>
                <div class="input-wrap">
                    <?= icon('link') ?>
                    <input class="input" id="ep-website" name="website" type="text" inputmode="url" maxlength="255" placeholder="https://"
                        value="<?= e($value('website')) ?>" spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'website', 'ep-website') ?>>
                </div>
                <?= field_error($errors, 'website', 'ep-website') ?>
            </div>
            <div class="field">
                <label class="field__label" for="ep-country"><?= e(t('País')) ?></label>
                <div class="select-wrap">
                    <?= icon('globe') ?>
                    <select class="select" id="ep-country" name="country"<?= invalid_attrs($errors, 'country', 'ep-country') ?>>
                        <option value=""><?= e(t('Sin especificar')) ?></option>
                        <?php foreach ($countries as $code => $name): ?>
                            <option value="<?= e($code) ?>" <?= $code === $countryCode ? 'selected' : '' ?>><?= e($name) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <?= field_error($errors, 'country', 'ep-country') ?>
            </div>
        </div>

        <div class="field">
            <label class="field__label" for="ep-birth"><?= e(t('Fecha de nacimiento')) ?></label>
            <div class="input-wrap">
                <?= icon('cake') ?>
                <input class="input" id="ep-birth" name="birth_date" type="date" max="<?= e(date('Y-m-d')) ?>" value="<?= e($value('birth_date')) ?>"<?= invalid_attrs($errors, 'birth_date', 'ep-birth') ?>>
            </div>
            <?= field_error($errors, 'birth_date', 'ep-birth') ?>
            <p class="field__hint"><?= e(t('No se muestra públicamente.')) ?></p>
        </div>

        <div class="setting-row">
            <div>
                <p class="setting-row__title"><?= icon('lock') ?> <?= e(t('Cuenta privada')) ?></p>
                <p class="setting-row__text"><?= e(t('Solo tus seguidores aprobados verán tus publicaciones, seguidores y seguidos.')) ?></p>
            </div>
            <label class="switch">
                <input type="checkbox" name="is_private" value="1" role="switch" <?= $isPrivate ? 'checked' : '' ?>>
                <span class="switch__track" aria-hidden="true"></span>
                <span class="sr-only"><?= e(t('Cuenta privada')) ?></span>
            </label>
        </div>
    </div>

    <div class="card form-card account-type" id="tipo-de-cuenta">
        <div>
            <h2 class="form-card__title"><?= icon('sparkles') ?> <?= e(t('Tipo de cuenta')) ?></h2>
            <p class="field__hint"><?= e(t('Las cuentas de creador muestran su categoría en el perfil. Los artistas musicales pueden publicar su música en TREVIX.')) ?></p>
        </div>
        <fieldset class="field account-type__options">
            <legend class="sr-only"><?= e(t('Tipo de cuenta')) ?></legend>
            <?php foreach (User::ACCOUNT_TYPES as $key => $label): ?>
                <label class="choice-card">
                    <input type="radio" name="account_type" value="<?= e($key) ?>" <?= $accountType === $key ? 'checked' : '' ?>>
                    <span class="choice-card__icon"><?= icon($key === 'creator' ? 'sparkles' : 'user') ?></span>
                    <span class="choice-card__text">
                        <strong><?= e(t($label)) ?></strong>
                        <span><?= e($key === 'creator' ? t('Elige tu categoría: artista musical, influencer, blogger u otra.') : t('Perfil personal, sin categoría de creador.')) ?></span>
                    </span>
                </label>
            <?php endforeach; ?>
            <?= field_error($errors, 'account_type', 'ep-account-type') ?>
        </fieldset>
        <fieldset class="field account-type__categories" data-creator-fields>
            <legend class="field__label"><?= e(t('Categoría de creador')) ?></legend>
            <div class="account-type__grid">
                <?php foreach (User::CREATOR_CATEGORIES as $key => $label): ?>
                    <label class="choice-card choice-card--compact">
                        <input type="radio" name="creator_category" value="<?= e($key) ?>" <?= $creatorCategory === $key ? 'checked' : '' ?>>
                        <span class="choice-card__icon"><?= icon(match ($key) {
                            'music_artist' => 'mic-vocal',
                            'influencer'   => 'star',
                            'blogger'      => 'file-text',
                            default        => 'sparkles',
                        }) ?></span>
                        <span class="choice-card__text"><strong><?= e(t($label)) ?></strong></span>
                    </label>
                <?php endforeach; ?>
            </div>
            <?= field_error($errors, 'creator_category', 'ep-creator-category') ?>
            <p class="field__hint"><?= icon('music') ?> <?= t('Con {category} se activa la sección Artista: subes tus canciones, el equipo las revisa y, al aprobarlas, entran en la biblioteca de música.', ['category' => '<strong>' . e(t('Artista musical')) . '</strong>']) ?></p>
        </fieldset>
    </div>

    <div class="form__actions">
        <a class="btn btn--ghost" href="<?= e(profile_url($viewer)) ?>"><?= e(t('Cancelar')) ?></a>
        <button type="submit" class="btn btn--primary"<?= $canEdit ? '' : ' disabled aria-disabled="true" data-tooltip="' . e(t('Inicia sesión para guardar cambios')) . '"' ?>><?= e(t('Guardar cambios')) ?></button>
    </div>
</form>
<script src="<?= e(asset('js/auth.js')) ?>" defer></script>
