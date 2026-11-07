<?php

use Trevix\Core\View;

/**
 * @var string      $tab         discover | mine
 * @var string      $term
 * @var string|null $category
 * @var array       $categories
 * @var array       $communities
 * @var string|null $nextUrl
 * @var bool        $isPreview
 */
$tabs = ['discover' => 'Descubrir', 'mine' => 'Mis comunidades'];
$filtered = $term !== '' || $category !== null;
?>
<header class="page-header">
    <div class="page-header__row page-header__row--between">
        <div>
            <h1 class="page-header__title page-header__title--visible">Comunidades</h1>
            <p class="page-header__subtitle">Espacios públicos y privados para compartir lo que te apasiona.</p>
        </div>
        <?php if ($isPreview): ?>
            <button type="button" class="btn btn--primary" disabled aria-disabled="true" data-tooltip="Inicia sesión para crear una comunidad"><?= icon('plus') ?> Crear comunidad</button>
        <?php else: ?>
            <a class="btn btn--primary" href="<?= e(url('communities.php', ['new' => 1])) ?>"><?= icon('plus') ?> Crear comunidad</a>
        <?php endif; ?>
    </div>
    <nav class="tabs" aria-label="Comunidades">
        <?php foreach ($tabs as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('communities.php', ['tab' => $key === 'discover' ? null : $key])) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<?php if ($tab === 'discover'): ?>
    <form class="community-filters" method="get" action="<?= e(url('communities.php')) ?>" role="search">
        <div class="search-field community-filters__search">
            <?= icon('search') ?>
            <label class="sr-only" for="community-q">Buscar comunidades</label>
            <input id="community-q" type="search" name="q" value="<?= e($term) ?>" maxlength="80" placeholder="Buscar comunidades" autocomplete="off">
        </div>
        <div class="select-wrap">
            <?= icon('layout-grid') ?>
            <label class="sr-only" for="community-category">Categoría</label>
            <select class="select" id="community-category" name="category" data-autosubmit>
                <option value="">Todas las categorías</option>
                <?php foreach ($categories as $option): ?>
                    <option value="<?= e($option) ?>" <?= $option === $category ? 'selected' : '' ?>><?= e($option) ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <button type="submit" class="btn btn--secondary">Buscar</button>
        <?php if ($filtered): ?>
            <a class="btn btn--ghost" href="<?= e(url('communities.php')) ?>">Limpiar</a>
        <?php endif; ?>
    </form>
<?php endif; ?>

<?php if ($communities === []): ?>
    <?php View::partial('empty-state', match (true) {
        $tab === 'mine' => [
            'icon' => 'users-round', 'heading' => 'Aún no perteneces a ninguna comunidad',
            'text' => 'Únete a una comunidad o crea la tuya para reunir a personas con tus mismos intereses.',
            'actionHref' => url('communities.php'), 'actionLabel' => 'Descubrir comunidades',
        ],
        $filtered => [
            'icon' => 'search', 'heading' => 'No encontramos comunidades',
            'text' => 'Prueba con otras palabras u otra categoría.',
        ],
        default => [
            'icon' => 'users-round', 'heading' => 'Todavía no hay comunidades',
            'text' => 'Sé la primera persona en crear una comunidad en TREVIX.',
            'actionHref' => $isPreview ? null : url('communities.php', ['new' => 1]), 'actionLabel' => 'Crear comunidad',
        ],
    }); ?>
<?php else: ?>
    <div class="community-grid">
        <?php foreach ($communities as $community): ?>
            <?php View::partial('community-card', ['community' => $community]); ?>
        <?php endforeach; ?>
    </div>
    <?php if ($nextUrl !== null): ?>
        <div class="community-more">
            <a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más comunidades</a>
        </div>
    <?php endif; ?>
<?php endif; ?>

<script src="<?= e(asset('js/communities.js')) ?>" defer></script>
