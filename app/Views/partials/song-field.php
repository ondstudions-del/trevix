<?php

use Trevix\Core\Config;
use Trevix\Core\View;

/**
 * Campo para adjuntar una canción de la biblioteca (lo maneja assets/js/music.js con el selector
 * #music-picker). Envía song_id y, en modo clip, song_start (segundo en que empieza el fragmento).
 * Si la canción actual ya no está disponible, los campos van deshabilitados: no se tocan salvo que
 * la persona la quite o elija otra.
 *
 * @var string     $mode    clip | full
 * @var array|null $song    canción actual (Song::cardsFor() + start)
 * @var bool       $withAdd muestra el botón «Añadir música» (si no, lo abre un botón externo con data-song-open)
 */
$mode = $mode ?? 'clip';
$song = $song ?? null;
$withAdd = $withAdd ?? false;
$available = $song !== null && !empty($song['available']);
$lock = $song !== null && !$available ? ' disabled' : '';
?>
<div class="song-field" data-song-field data-song-mode="<?= e($mode) ?>" data-song-clip="<?= (int) Config::get('app.limits.song_clip_seconds', 30) ?>">
    <input type="hidden" name="song_id" value="<?= $available ? (int) $song['id'] : '' ?>" data-song-id<?= $lock ?>>
    <?php if ($mode === 'clip'): ?>
        <input type="hidden" name="song_start" value="<?= (int) ($song['start'] ?? 0) ?>" data-song-start<?= $lock ?>>
    <?php endif; ?>
    <?php if ($withAdd): ?>
        <button type="button" class="btn btn--secondary btn--sm song-field__add js-only" data-song-pick<?= $song !== null ? ' hidden' : '' ?>>
            <?= icon('music') ?> <?= e(t('Añadir música')) ?>
        </button>
    <?php endif; ?>
    <div class="song-field__selected" data-song-selected<?= $song === null ? ' hidden' : '' ?>>
        <div class="song-field__chip" data-song-chip>
            <?php if ($song !== null): ?>
                <?php View::partial('song-chip', ['song' => $song, 'mode' => $mode]); ?>
            <?php endif; ?>
        </div>
        <div class="song-field__actions js-only">
            <button type="button" class="btn btn--ghost btn--sm" data-song-pick><?= icon('music') ?> <?= e($mode === 'clip' ? t('Cambiar o ajustar') : t('Cambiar')) ?></button>
            <button type="button" class="btn btn--ghost btn--sm" data-song-remove><?= icon('x') ?> <?= e(t('Quitar')) ?></button>
        </div>
    </div>
</div>
