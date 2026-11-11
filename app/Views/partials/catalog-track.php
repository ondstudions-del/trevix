<?php
/**
 * Pista de Audius o Free To Use que todavía no se usó en TREVIX: se escucha desde el catálogo y «Usar» la guarda
 * como canción (api/music.php action=import) y abre su ficha.
 *
 * @var array $track MusicCatalog (source, source_label, external_id, title, artist, genre_label, duration, audio_url, cover_url, page_url)
 */
?>
<article class="song-row">
    <div class="song-chip song-chip--md" data-song-player>
        <button type="button" class="song-chip__play js-only" data-song-toggle aria-label="<?= e(t('Escuchar «{title}»', ['title' => $track['title']])) ?>">
            <span class="song-chip__icon-play"><?= icon('play') ?></span>
            <span class="song-chip__icon-pause"><?= icon('pause') ?></span>
        </button>
        <span class="song-chip__cover" aria-hidden="true">
            <?php if ($track['cover_url'] !== null): ?>
                <img src="<?= e($track['cover_url']) ?>" alt="" loading="lazy">
            <?php else: ?>
                <?= icon('music') ?>
            <?php endif; ?>
        </span>
        <span class="song-chip__info">
            <span class="song-chip__title"><?= e($track['title']) ?></span>
            <span class="song-chip__artist"><?= e($track['artist']) ?> · <?= e($track['source_label']) ?></span>
            <span class="song-chip__bar" aria-hidden="true"><span data-song-progress></span></span>
        </span>
        <span class="song-chip__time" data-song-time><?= e(sprintf('%d:%02d', intdiv($track['duration'], 60), $track['duration'] % 60)) ?></span>
        <audio preload="none" src="<?= e($track['audio_url']) ?>" data-start="0" data-end="0"></audio>
    </div>
    <p class="song-row__meta"><span><?= e(t($track['genre_label'])) ?></span><span><?= e(t('vía {source}', ['source' => $track['source_label']])) ?></span></p>
    <div class="song-row__actions">
        <form method="post" action="<?= e(url('api/music.php')) ?>">
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="import">
            <input type="hidden" name="source" value="<?= e($track['source']) ?>">
            <input type="hidden" name="external_id" value="<?= e($track['external_id']) ?>">
            <button type="submit" class="btn btn--secondary btn--sm"><?= icon('plus') ?> <?= e(t('Usar')) ?></button>
        </form>
        <?php if ($track['source'] === 'audius' && $track['page_url'] !== null): ?>
            <a class="icon-btn" href="<?= e($track['page_url']) ?>" target="_blank" rel="noopener noreferrer"
                aria-label="<?= e(t('Ver «{title}» en Audius', ['title' => $track['title']])) ?>" data-tooltip="<?= e(t('Ver en Audius')) ?>"><?= icon('external-link') ?></a>
        <?php endif; ?>
    </div>
</article>
