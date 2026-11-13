<?php
/**
 * Tarjeta de una lista de reproducción de reels (perfil del creador).
 *
 * @var array $playlist Playlist::find() / forUser()
 */
?>
<a class="playlist-card" href="<?= e(url('playlist.php', ['id' => $playlist['id']])) ?>">
    <span class="playlist-card__cover">
        <?php if (!empty($playlist['cover_path'])): ?>
            <img src="<?= e(url($playlist['cover_path'])) ?>" alt="" loading="lazy" decoding="async">
        <?php else: ?>
            <?= icon('list') ?>
        <?php endif; ?>
        <span class="playlist-card__count"><?= icon('play') ?> <?= (int) $playlist['items_count'] ?></span>
    </span>
    <span class="playlist-card__title"><?= e($playlist['title']) ?></span>
    <span class="playlist-card__meta"><?= e(t('{n} videos', ['n' => (int) $playlist['items_count']])) ?></span>
</a>
