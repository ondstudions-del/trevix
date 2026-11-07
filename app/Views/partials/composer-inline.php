<?php
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
    $community !== null => 'Publica algo en ' . $community['name'] . '…',
    $format === 'thread' => 'Inicia una conversación…',
    default => '¿Qué quieres compartir' . ($firstName !== '' ? ', ' . $firstName : '') . '?',
};
$target = $community !== null
    ? ' data-composer-community="' . (int) $community['id'] . '" data-composer-community-name="' . e($community['name']) . '"'
    : '';
?>
<section class="card composer-inline" aria-label="Crear publicación">
    <?= $viewer ? avatar($viewer, 'md') : '' ?>
    <button type="button" class="composer-inline__prompt" data-open-composer data-composer-format="<?= e($format) ?>"<?= $target ?>>
        <?= e($prompt) ?>
    </button>
    <div class="composer-inline__tools">
        <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-pick="image" aria-label="Agregar imágenes" data-tooltip="Imagen"<?= $target ?>>
            <?= icon('image') ?>
        </button>
        <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-pick="video" aria-label="Agregar video" data-tooltip="Video"<?= $target ?>>
            <?= icon('video') ?>
        </button>
        <button type="button" class="icon-btn icon-btn--accent" data-open-composer data-composer-format="thread" aria-label="Escribir un hilo" data-tooltip="Hilo"<?= $target ?>>
            <?= icon('messages-square') ?>
        </button>
    </div>
</section>
