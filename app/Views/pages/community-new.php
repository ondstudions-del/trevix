<?php

use Trevix\Core\Config;

/**
 * @var array      $categories
 * @var array      $visibilities
 * @var array      $errors
 * @var array      $old
 * @var bool       $isPreview
 */
$limits = Config::get('app.limits');
$visibility = (string) ($old['visibility'] ?? 'public');
$visibilityText = [
    'public'  => ['globe', t('Cualquiera puede ver las publicaciones y unirse al instante.')],
    'private' => ['lock', t('Solo los miembros ven las publicaciones. Tú y tus moderadores aprueban cada solicitud.')],
];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('communities.php')) ?>" aria-label="<?= e(t('Volver a comunidades')) ?>"><?= icon('arrow-left') ?></a>
        <div>
            <h1 class="page-header__title page-header__title--visible"><?= e(t('Crear comunidad')) ?></h1>
            <p class="page-header__subtitle"><?= e(t('Reúne a personas alrededor de un tema. Podrás cambiar la foto y la portada después.')) ?></p>
        </div>
    </div>
</header>

<form class="form community-form" method="post" action="<?= e(url('api/communities.php')) ?>" novalidate data-validate>
    <?= csrf_field() ?>
    <input type="hidden" name="action" value="create">

    <div class="card form-card">
        <div class="field">
            <label class="field__label" for="cm-name"><?= e(t('Nombre')) ?></label>
            <input class="input" id="cm-name" name="name" type="text" minlength="3" maxlength="<?= (int) $limits['community_name'] ?>" required
                data-rule="required" value="<?= e($old['name'] ?? '') ?>" data-char-count="#cm-name-count" autocomplete="off"<?= invalid_attrs($errors, 'name', 'cm-name') ?>>
            <?= field_error($errors, 'name', 'cm-name') ?>
            <p class="field__hint"><span id="cm-name-count"></span> · <?= e(t('La dirección de la comunidad se genera a partir del nombre y no cambia.')) ?></p>
        </div>

        <div class="field">
            <label class="field__label" for="cm-description"><?= e(t('Descripción')) ?> <span class="field__optional"><?= e(t('(opcional)')) ?></span></label>
            <textarea class="input textarea" id="cm-description" name="description" rows="3" maxlength="<?= (int) $limits['community_description'] ?>" data-autosize
                data-char-count="#cm-description-count"<?= invalid_attrs($errors, 'description', 'cm-description') ?>><?= e($old['description'] ?? '') ?></textarea>
            <?= field_error($errors, 'description', 'cm-description') ?>
            <p class="field__hint"><span id="cm-description-count"></span> · <?= e(t('Cuenta de qué trata y qué se espera de sus miembros.')) ?></p>
        </div>

        <div class="field">
            <label class="field__label" for="cm-category"><?= e(t('Categoría')) ?></label>
            <div class="select-wrap">
                <?= icon('layout-grid') ?>
                <select class="select" id="cm-category" name="category" required data-rule="required"<?= invalid_attrs($errors, 'category', 'cm-category') ?>>
                    <option value=""><?= e(t('Elige una categoría')) ?></option>
                    <?php foreach ($categories as $option): ?>
                        <option value="<?= e($option) ?>" <?= ($old['category'] ?? '') === $option ? 'selected' : '' ?>><?= e(t($option)) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <?= field_error($errors, 'category', 'cm-category') ?>
        </div>

        <fieldset class="field community-form__visibility">
            <legend class="field__label"><?= e(t('Visibilidad')) ?></legend>
            <?php foreach ($visibilities as $key => $label): ?>
                <?php [$visIcon, $visText] = $visibilityText[$key]; ?>
                <label class="choice-card">
                    <input type="radio" name="visibility" value="<?= e($key) ?>" <?= $visibility === $key ? 'checked' : '' ?>>
                    <span class="choice-card__icon"><?= icon($visIcon) ?></span>
                    <span class="choice-card__text">
                        <strong><?= e(t($label)) ?></strong>
                        <span><?= e($visText) ?></span>
                    </span>
                </label>
            <?php endforeach; ?>
            <?= field_error($errors, 'visibility', 'cm-visibility') ?>
        </fieldset>
    </div>

    <div class="form__actions">
        <a class="btn btn--ghost" href="<?= e(url('communities.php')) ?>"><?= e(t('Cancelar')) ?></a>
        <button type="submit" class="btn btn--primary"<?= $isPreview ? ' disabled aria-disabled="true" data-tooltip="' . e(t('Inicia sesión para crear una comunidad')) . '"' : '' ?>><?= e(t('Crear comunidad')) ?></button>
    </div>
</form>
<script src="<?= e(asset('js/auth.js')) ?>" defer></script>
