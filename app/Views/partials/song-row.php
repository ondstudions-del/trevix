<?php

use Trevix\Core\Auth;
use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Canción de la biblioteca con su reproductor (canción completa) y los accesos para usarla.
 *
 * @var array $song Song::cardsFor() / Song::library()
 */
$canUse = Auth::check();
?>
<article class="song-row">
    <?php View::partial('song-chip', ['song' => $song, 'mode' => 'full']); ?>
    <p class="song-row__meta">
        <span><?= e(Song::GENRES[$song['genre']] ?? 'Otro') ?></span>
        <span aria-hidden="true">·</span>
        <span><?= e(compact_number($song['uses_count'])) ?> <?= plural($song['uses_count'], 'uso', 'usos') ?></span>
    </p>
    <div class="song-row__actions">
        <?php if ($canUse): ?>
            <button type="button" class="icon-btn js-only" data-open-composer
                data-composer-song="<?= e((string) json_encode(song_client($song), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)) ?>"
                aria-label="Usar «<?= e($song['title']) ?>» en una publicación" data-tooltip="Usar en publicación"><?= icon('pencil') ?></button>
            <a class="icon-btn" href="<?= e(url('stories.php', ['new' => 1, 'song' => $song['id']])) ?>"
                aria-label="Usar «<?= e($song['title']) ?>» en una historia" data-tooltip="Usar en historia"><?= icon('circle-dashed') ?></a>
        <?php endif; ?>
        <a class="icon-btn" href="<?= e(url('music.php', ['id' => $song['id']])) ?>"
            aria-label="Ver «<?= e($song['title']) ?>»" data-tooltip="Ver canción"><?= icon('chevron-right') ?></a>
    </div>
</article>
