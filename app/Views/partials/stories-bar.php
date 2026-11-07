<?php
/**
 * @var array      $stories  [{user, seen}] propias primero (si hay) y luego las de las cuentas que sigues
 * @var array|null $viewer
 */
$ownStory = null;
if ($viewer) {
    foreach ($stories as $story) {
        if ($story['user']['username'] === $viewer['username']) {
            $ownStory = $story;
        }
    }
}
?>
<section class="stories" aria-label="Historias" data-stories>
    <button type="button" class="stories__nav stories__nav--prev" data-stories-prev aria-label="Ver historias anteriores" hidden>
        <?= icon('chevron-left') ?>
    </button>
    <ul class="stories__track" data-stories-track>
        <?php if ($viewer && $ownStory !== null): ?>
            <li class="stories__own">
                <a class="story" href="<?= e(url('stories.php', ['u' => $viewer['username']])) ?>" aria-label="Ver tu historia">
                    <span class="story__ring"><?= avatar($viewer, 'lg') ?></span>
                    <span class="story__name">Tu historia</span>
                </a>
                <a class="story__add story__add--link" href="<?= e(url('stories.php', ['new' => 1])) ?>" aria-label="Crear otra historia" data-tooltip="Nueva historia"><?= icon('plus') ?></a>
            </li>
        <?php elseif ($viewer): ?>
            <li>
                <a class="story story--own" href="<?= e(url('stories.php', ['new' => 1])) ?>" aria-label="Crear una historia">
                    <span class="story__ring story__ring--own">
                        <?= avatar($viewer, 'lg') ?>
                        <span class="story__add"><?= icon('plus') ?></span>
                    </span>
                    <span class="story__name">Tu historia</span>
                </a>
            </li>
        <?php endif; ?>
        <?php foreach ($stories as $story): ?>
            <?php $user = $story['user']; ?>
            <?php if ($ownStory !== null && $story === $ownStory) { continue; } ?>
            <li>
                <a class="<?= cx('story', ['story--seen' => $story['seen']]) ?>" href="<?= e(url('stories.php', ['u' => $user['username']])) ?>"
                    aria-label="Ver historia de <?= e($user['display_name']) ?><?= $story['seen'] ? ' (vista)' : '' ?>">
                    <span class="story__ring"><?= avatar($user, 'lg') ?></span>
                    <span class="story__name"><?= e(explode(' ', $user['display_name'])[0]) ?></span>
                </a>
            </li>
        <?php endforeach; ?>
    </ul>
    <button type="button" class="stories__nav stories__nav--next" data-stories-next aria-label="Ver más historias" hidden>
        <?= icon('chevron-right') ?>
    </button>
</section>
