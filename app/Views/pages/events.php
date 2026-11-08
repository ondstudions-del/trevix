<?php

use Trevix\Core\View;

/**
 * @var string     $tab     upcoming | past
 * @var array      $tabs
 * @var array      $list    ['posts' => [...], 'nextUrl' => ?string] publicaciones con evento
 * @var string     $endText
 * @var array|null $viewer
 */
?>
<header class="page-header page-header--sticky">
    <h1 class="page-header__title">Eventos</h1>
    <nav class="tabs" aria-label="Eventos">
        <?php foreach ($tabs as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('events.php', ['tab' => $key === 'upcoming' ? null : $key])) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<?php if ($viewer): ?>
    <div class="events-create">
        <button type="button" class="btn btn--primary js-only" data-open-composer data-composer-panel="event"><?= icon('calendar-plus') ?> Crear evento</button>
    </div>
<?php endif; ?>

<section class="feed" aria-label="Eventos · <?= e($tabs[$tab]) ?>">
    <?php if ($list['posts'] === []): ?>
        <?php View::partial('empty-state', [
            'icon'    => 'calendar',
            'heading' => $tab === 'upcoming' ? 'No hay eventos próximos' : 'Todavía no hay eventos pasados',
            'text'    => $tab === 'upcoming' ? 'Cuando alguien que puedes ver cree un evento, aparecerá aquí.' : 'Los eventos que ya terminaron se guardan en esta pestaña.',
        ]); ?>
    <?php else: ?>
        <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => $endText]); ?>
    <?php endif; ?>
</section>
