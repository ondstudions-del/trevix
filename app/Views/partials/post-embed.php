<?php
/** @var array $post Publicación compartida (citada) dentro de otra. */
$author = $post['user'];
$cover = $post['media'][0] ?? null;
$extra = count($post['media'] ?? []) - 1;
?>
<div class="post-embed">
    <div class="post-embed__byline">
        <?= avatar($author, 'xs') ?>
        <a class="post-embed__author" href="<?= e(profile_url($author)) ?>"><?= e($author['display_name']) ?></a>
        <?= !empty($author['is_verified']) ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
        <span class="post__handle">@<?= e($author['username']) ?></span>
        <span class="post__dot" aria-hidden="true">·</span>
        <?= time_tag($post['created_at']) ?>
    </div>
    <?php if (($post['body'] ?? '') !== ''): ?>
        <p class="post-embed__body"><?= format_post_body($post['body']) ?></p>
    <?php endif; ?>
    <?php if ($cover && $cover['type'] === 'image'): ?>
        <img class="post-embed__media" src="<?= e(url($cover['src'])) ?>" alt="<?= e($cover['alt'] ?? '') ?>" loading="lazy" decoding="async">
    <?php elseif ($cover && $cover['type'] === 'video'): ?>
        <video class="post-embed__media" src="<?= e(url($cover['src'])) ?>"<?= !empty($cover['poster']) ? ' poster="' . e(url($cover['poster'])) . '"' : '' ?> controls preload="metadata" playsinline></video>
    <?php endif; ?>
    <?php if (!empty($post['song'])): ?>
        <?php \Trevix\Core\View::partial('song-chip', ['song' => $post['song'], 'mode' => 'clip']); ?>
    <?php endif; ?>
    <?php if (!empty($post['id'])): ?>
        <a class="post-embed__link" href="<?= e(url('post.php', ['id' => $post['id']])) ?>">
            <?= e(t('Ver publicación original')) ?><?= $extra > 0 ? ' · ' . e(tn($extra, '{n} archivo más', '{n} archivos más')) : '' ?>
        </a>
    <?php endif; ?>
</div>
