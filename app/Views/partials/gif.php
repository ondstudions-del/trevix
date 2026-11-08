<?php
/**
 * GIF o sticker de GIPHY en un comentario o mensaje (Giphy::fromRow).
 *
 * @var array $gif
 */
$maxWidth = $gif['kind'] === 'sticker' ? 140 : 220;
$width = min($maxWidth, max(1, $gif['width']));
$height = (int) round($gif['height'] * $width / max(1, $gif['width']));
?>
<img class="<?= cx('gif', 'gif--' . $gif['kind']) ?>" src="<?= e($gif['url']) ?>" width="<?= $width ?>" height="<?= $height ?>"
    alt="<?= e($gif['title'] !== '' ? $gif['title'] : ($gif['kind'] === 'sticker' ? 'Sticker' : 'GIF')) ?>" loading="lazy" decoding="async"
    referrerpolicy="no-referrer">
