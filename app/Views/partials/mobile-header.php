<?php

use Trevix\Core\View;

/** @var array|null $viewer */
$unreadMessages = (int) ($viewer['unread_messages'] ?? 0);
?>
<header class="mobile-header">
    <a class="mobile-header__brand" href="<?= e(url('feed.php')) ?>" aria-label="TREVIX, ir al inicio">
        <?php View::partial('logo', ['size' => 30, 'wordmark' => true]); ?>
    </a>
    <div class="mobile-header__actions">
        <?php if (\Trevix\Models\User::isMusicArtist($viewer)): ?>
            <a class="icon-btn" href="<?= e(url('artist.php')) ?>" aria-label="Artista"><?= icon('mic-vocal') ?></a>
        <?php endif; ?>
        <a class="icon-btn" href="<?= e(url('music.php')) ?>" aria-label="Música"><?= icon('music') ?></a>
        <a class="icon-btn" href="<?= e(url('messages.php')) ?>" aria-label="Mensajes" data-badge="messages" data-badge-style="dot">
            <?= icon('send') ?>
            <?php if ($unreadMessages > 0): ?><span class="badge-dot" aria-hidden="true"></span><?php endif; ?>
        </a>
    </div>
</header>
