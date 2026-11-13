<?php

use Trevix\Models\User;

/**
 * Acceso rápido al compositor dentro del feed o de una comunidad.
 *
 * @var array|null $viewer
 * @var string     $format    post | thread
 * @var array|null $community si se indica, lo publicado va a esa comunidad
 */
$format = $format ?? 'post';
$community = $community ?? null;
$firstName = explode(' ', (string) ($viewer['display_name'] ?? ''))[0];
$prompt = match (true) {
    $community !== null => t('Publica algo en {name}…', ['name' => $community['name']]),
    $format === 'thread' => t('Inicia una conversación…'),
    $firstName !== '' => t('¿Qué quieres compartir, {name}?', ['name' => $firstName]),
    default => t('¿Qué quieres compartir?'),
};
$target = $community !== null
    ? ' data-composer-community="' . (int) $community['id'] . '" data-composer-community-name="' . e($community['name']) . '"'
    : '';
?>
<section class="card composer-inline" aria-label="<?= e(t('Crear publicación')) ?>">
    <?= $viewer ? avatar($viewer, 'md') : '' ?>
    <button type="button" class="composer-inline__prompt" data-open-composer data-composer-format="<?= e($format) ?>"<?= $target ?>>
        <?= e($prompt) ?>
    </button>
    <div class="composer-inline__tools">
        <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-pick="image" aria-label="<?= e(t('Agregar imágenes')) ?>" data-tooltip="<?= e(t('Imagen')) ?>"<?= $target ?>>
            <?= icon('image') ?>
        </button>
        <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-pick="video" aria-label="<?= e(t('Agregar video')) ?>" data-tooltip="<?= e(t('Video')) ?>"<?= $target ?>>
            <?= icon('video') ?>
        </button>
        <?php if (!User::isCreator($viewer)): ?>
            <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-format="thread" aria-label="<?= e(t('Escribir un hilo')) ?>" data-tooltip="<?= e(t('Hilo')) ?>"<?= $target ?>>
                <?= icon('messages-square') ?>
            </button>
        <?php endif; ?>
    </div>
</section>
