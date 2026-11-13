<?php

use Trevix\Core\Config;

/**
 * Música de una publicación en su tarjeta. En las fotos y textos con música se ve una línea corta bajo el autor con
 * la canción y un botón para silenciar: la canción suena sola mientras la publicación está a la vista (music.js).
 * En los videos no se muestra nada (la canción se ve en los reels); el audio queda para los grabados sobre la canción.
 *
 * @var array $song       Song::cardsFor() + start
 * @var bool  $video      la publicación tiene video
 * @var ?int  $clipLength segundos del fragmento si no es el habitual (video grabado sobre la canción, hasta 60 s)
 */
$video = $video ?? false;
if (empty($song['available'])) {
    return;
}
$start = (int) ($song['start'] ?? 0);
$clip = !empty($clipLength) ? min(60, (int) $clipLength) : (int) Config::get('app.limits.song_clip_seconds', 30);
$end = min((int) $song['duration'], $start + $clip);
$artist = $song['artist']['display_name'] . (!empty($song['featuring']) ? ' · feat. ' . $song['featuring'] : '');
?>
<div class="post__song post-song" data-post-song<?= $video ? ' hidden' : ' data-autoplay' ?>>
    <?php if (!$video): ?>
        <a class="post-song__name" href="<?= e(url('music.php', ['id' => $song['id']])) ?>">
            <?= icon('music') ?>
            <span class="post-song__text"><?= e($song['title']) ?> · <?= e($artist) ?></span>
            <?php if (!empty($song['is_explicit'])): ?><abbr class="song-chip__explicit" title="<?= e(t('Contenido explícito')) ?>">E</abbr><?php endif; ?>
        </a>
        <button type="button" class="post-song__mute js-only" data-song-mute aria-pressed="false"
            aria-label="<?= e(t('Silenciar la música de las publicaciones')) ?>" data-tooltip="<?= e(t('Sonido de las publicaciones')) ?>">
            <span class="post-song__on"><?= icon('volume-2') ?></span>
            <span class="post-song__off"><?= icon('volume-x') ?></span>
        </button>
    <?php endif; ?>
    <audio preload="none" src="<?= e(url($song['src'])) ?>" data-start="<?= $start ?>" data-end="<?= $end ?>"></audio>
</div>
