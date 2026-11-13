<?php

use Trevix\Core\View;

/**
 * Lista de reproducción de reels: sus videos en el orden en que se agregaron. Quien la creó puede editarla,
 * quitar videos o eliminarla.
 *
 * @var array      $playlist Playlist::find()
 * @var array      $list     ['posts' => [...], 'nextUrl' => ?string]
 * @var bool       $isOwn
 * @var array|null $viewer
 */
$owner = $playlist['user'];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('profile.php', ['u' => $owner['username'], 'tab' => 'lists'])) ?>" aria-label="<?= e(t('Volver al perfil')) ?>" data-tooltip="<?= e(t('Perfil')) ?>"><?= icon('chevron-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Lista de reproducción')) ?></h1>
    </div>
</header>

<section class="card playlist-hero" aria-labelledby="playlist-title">
    <div class="playlist-hero__cover">
        <?php if (!empty($playlist['cover_path'])): ?>
            <img src="<?= e(url($playlist['cover_path'])) ?>" alt="">
        <?php else: ?>
            <?= icon('list') ?>
        <?php endif; ?>
    </div>
    <div class="playlist-hero__info">
        <h2 class="playlist-hero__title" id="playlist-title"><?= e($playlist['title']) ?></h2>
        <p class="playlist-hero__owner">
            <a href="<?= e(profile_url($owner)) ?>"><?= avatar($owner, 'xs') ?> <?= e($owner['display_name']) ?></a>
            <?= !empty($owner['is_verified']) ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
            · <?= e(t('{n} videos', ['n' => (int) $playlist['items_count']])) ?>
        </p>
        <?php if ($playlist['description'] !== ''): ?>
            <p class="playlist-hero__description"><?= nl2br(e($playlist['description'])) ?></p>
        <?php endif; ?>
        <p class="playlist-hero__hint"><?= icon('list') ?> <?= e(t('Los videos se reproducen en el orden en que se publicaron en la lista.')) ?></p>
    </div>
    <?php if ($isOwn): ?>
        <details class="playlist-edit">
            <summary class="btn btn--secondary"><?= icon('pencil') ?> <?= e(t('Editar lista')) ?></summary>
            <form class="playlist-edit__form" method="post" action="<?= e(url('api/playlists.php')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="playlist_id" value="<?= (int) $playlist['id'] ?>">
                <label class="field">
                    <span class="field__label"><?= e(t('Nombre')) ?></span>
                    <input class="input" type="text" name="title" required maxlength="80" value="<?= e($playlist['title']) ?>">
                </label>
                <label class="field">
                    <span class="field__label"><?= e(t('Descripción (opcional)')) ?></span>
                    <textarea class="input" name="description" rows="2" maxlength="300"><?= e($playlist['description']) ?></textarea>
                </label>
                <button type="submit" class="btn btn--primary"><?= e(t('Guardar')) ?></button>
            </form>
            <form method="post" action="<?= e(url('api/playlists.php')) ?>"
                data-confirm="<?= e(t('¿Eliminar la lista «{title}»? Los videos seguirán publicados.', ['title' => $playlist['title']])) ?>" data-confirm-label="<?= e(t('Eliminar')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="playlist_id" value="<?= (int) $playlist['id'] ?>">
                <button type="submit" class="btn btn--danger"><?= icon('trash-2') ?> <?= e(t('Eliminar lista')) ?></button>
            </form>
        </details>
    <?php endif; ?>
</section>

<section class="playlist-items feed" aria-labelledby="playlist-title">
    <?php if ($list['posts'] === []): ?>
        <?php View::partial('empty-state', $isOwn
            ? ['icon' => 'film', 'heading' => 'La lista está vacía', 'text' => 'Abre el menú «⋯» de uno de tus reels y elige «Agregar a una lista».']
            : ['icon' => 'film', 'heading' => 'La lista está vacía', 'text' => 'Cuando agregue videos, los verás aquí.']); ?>
    <?php else: ?>
        <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => t('Ya viste todos los videos de la lista.')]); ?>
    <?php endif; ?>
</section>
