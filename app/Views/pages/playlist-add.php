<?php
/**
 * Elegir en qué listas de reproducción va un video propio (agregar, quitar o crear una lista nueva con él).
 *
 * @var array $post      Post::findVisible()
 * @var array $playlists Playlist::forUser() con has_post
 * @var bool  $isCreator
 */
$poster = null;
foreach ($post['media'] as $item) {
    if ($item['type'] === 'video') {
        $poster = $item['poster'] ?? null;
        break;
    }
}
$hasVideo = array_filter($post['media'], static fn (array $m): bool => $m['type'] === 'video') !== [];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('post.php', ['id' => $post['id']])) ?>" aria-label="<?= e(t('Volver a la publicación')) ?>" data-tooltip="<?= e(t('Publicación')) ?>"><?= icon('chevron-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Agregar a una lista')) ?></h1>
    </div>
</header>

<section class="card playlist-pick">
    <div class="playlist-pick__post">
        <span class="playlist-pick__thumb">
            <?php if ($poster !== null): ?>
                <img src="<?= e(url($poster)) ?>" alt="">
            <?php else: ?>
                <?= icon('film') ?>
            <?php endif; ?>
        </span>
        <span class="playlist-pick__text"><?= e(mb_strimwidth(plain_body((string) $post['body']), 0, 120, '…') ?: t('Video sin descripción')) ?></span>
    </div>

    <?php if (!$isCreator): ?>
        <p class="playlist-pick__notice"><?= e(t('Las listas de reproducción son para cuentas de creador de contenido. Actívalo en Configuración › Cuenta.')) ?></p>
    <?php elseif (!$hasVideo): ?>
        <p class="playlist-pick__notice"><?= e(t('Las listas de reproducción son de videos (reels).')) ?></p>
    <?php else: ?>
        <?php if ($playlists !== []): ?>
            <ul class="playlist-pick__list">
                <?php foreach ($playlists as $playlist): ?>
                    <li class="playlist-pick__row">
                        <a class="playlist-pick__name" href="<?= e(url('playlist.php', ['id' => $playlist['id']])) ?>">
                            <?= icon('list') ?> <?= e($playlist['title']) ?>
                            <span class="playlist-pick__count"><?= e(t('{n} videos', ['n' => (int) $playlist['items_count']])) ?></span>
                        </a>
                        <form method="post" action="<?= e(url('api/playlists.php')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="<?= $playlist['has_post'] ? 'remove' : 'add' ?>">
                            <input type="hidden" name="playlist_id" value="<?= (int) $playlist['id'] ?>">
                            <input type="hidden" name="post_id" value="<?= (int) $post['id'] ?>">
                            <input type="hidden" name="return" value="add">
                            <?php if ($playlist['has_post']): ?>
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('check') ?> <?= e(t('En la lista · Quitar')) ?></button>
                            <?php else: ?>
                                <button type="submit" class="btn btn--primary btn--sm"><?= icon('plus') ?> <?= e(t('Agregar')) ?></button>
                            <?php endif; ?>
                        </form>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
        <form class="playlist-pick__new" method="post" action="<?= e(url('api/playlists.php')) ?>">
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="create">
            <input type="hidden" name="post_id" value="<?= (int) $post['id'] ?>">
            <input type="hidden" name="return" value="add">
            <label class="field">
                <span class="field__label"><?= e(t('Nueva lista con este video')) ?></span>
                <input class="input" type="text" name="title" required maxlength="80" placeholder="<?= e(t('Nombre de la lista')) ?>">
            </label>
            <button type="submit" class="btn btn--secondary"><?= icon('plus') ?> <?= e(t('Crear lista')) ?></button>
        </form>
    <?php endif; ?>
</section>
