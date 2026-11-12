<?php

use Trevix\Core\Config;

/**
 * Canción adjunta con su reproductor. En publicaciones e historias suena el fragmento elegido;
 * en mensajes, la biblioteca y el perfil del artista, la canción completa.
 *
 * @var array  $song  Song::cardsFor() + start
 * @var string $mode  clip | full
 * @var string $size  md | lg
 * @var bool   $link  enlaza a la ficha de la canción (solo existe si está publicada)
 * @var ?int   $clipLength  segundos del fragmento si no es el habitual (video grabado sobre la canción, hasta 60 s)
 */
$mode = $mode ?? 'clip';
$size = $size ?? 'md';
$link = $link ?? true;
if (empty($song['available'])): ?>
    <div class="song-chip song-chip--off" role="note">
        <span class="song-chip__cover"><?= icon('music') ?></span>
        <span class="song-chip__info"><span class="song-chip__title"><?= e(t('Canción no disponible')) ?></span></span>
    </div>
<?php return; endif;

$start = $mode === 'clip' ? (int) ($song['start'] ?? 0) : 0;
$clip = !empty($clipLength) ? min(60, (int) $clipLength) : (int) Config::get('app.limits.song_clip_seconds', 30);
$end = $mode === 'clip' ? min($song['duration'], $start + $clip) : 0;
$length = $mode === 'clip' ? $end - $start : $song['duration'];
$songUrl = url('music.php', ['id' => $song['id']]);
$artist = $song['artist']['display_name'] . (!empty($song['featuring']) ? ' · feat. ' . $song['featuring'] : '')
    . (($song['source'] ?? 'trevix') !== 'trevix' ? ' · ' . $song['source_label'] : '');
?>
<div class="<?= cx('song-chip', 'song-chip--' . $size) ?>" data-song-player>
    <button type="button" class="song-chip__play js-only" data-song-toggle aria-label="<?= e(t('Reproducir «{title}»', ['title' => $song['title']])) ?>">
        <span class="song-chip__icon-play"><?= icon('play') ?></span>
        <span class="song-chip__icon-pause"><?= icon('pause') ?></span>
    </button>
    <<?= $link ? 'a href="' . e($songUrl) . '" tabindex="-1"' : 'span' ?> class="song-chip__cover" aria-hidden="true">
        <?php if (!empty($song['cover'])): ?>
            <img src="<?= e(url($song['cover'])) ?>" alt="" loading="lazy">
        <?php else: ?>
            <?= icon('music') ?>
        <?php endif; ?>
    </<?= $link ? 'a' : 'span' ?>>
    <span class="song-chip__info">
        <<?= $link ? 'a href="' . e($songUrl) . '"' : 'span' ?> class="song-chip__title">
            <?= e($song['title']) ?>
            <?php if ($song['is_explicit']): ?><abbr class="song-chip__explicit" title="<?= e(t('Contenido explícito')) ?>">E</abbr><?php endif; ?>
        </<?= $link ? 'a' : 'span' ?>>
        <span class="song-chip__artist"><?= e($artist) ?></span>
        <span class="song-chip__bar" aria-hidden="true"><span data-song-progress></span></span>
    </span>
    <span class="song-chip__time" data-song-time><?= e(sprintf('%d:%02d', intdiv($length, 60), $length % 60)) ?></span>
    <audio preload="none" src="<?= e(url($song['src'])) ?>" data-start="<?= $start ?>" data-end="<?= $end ?>"></audio>
</div>
