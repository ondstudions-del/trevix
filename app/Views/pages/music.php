<?php

use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Catálogo de música único: canciones de artistas de TREVIX (aprobadas por el equipo) y pistas de Audius y
 * Free To Use en una sola lista, para escucharlas y usarlas en publicaciones e historias.
 *
 * @var string      $term
 * @var string|null $genre
 * @var string      $sort    recent | popular (ordena las canciones de TREVIX)
 * @var list<array{source:string, song:?array, track:?array}> $items MusicService::browse
 * @var list<string> $unavailable catálogos externos que no respondieron
 * @var string|null $nextUrl
 * @var bool        $isArtist
 * @var bool        $isPreview
 */
$filtered = $term !== '' || $genre !== null;
$sources = array_unique(array_column($items, 'source'));
?>
<header class="page-header">
    <div class="page-header__row page-header__row--between">
        <div>
            <h1 class="page-header__title page-header__title--visible">Música</h1>
            <p class="page-header__subtitle">Canciones de artistas de TREVIX, Audius y Free To Use en un solo catálogo, para tus publicaciones e historias.</p>
        </div>
        <?php if ($isArtist): ?>
            <a class="btn btn--primary" href="<?= e(url('artist.php')) ?>#subir"><?= icon('upload') ?> Subir canción</a>
        <?php endif; ?>
    </div>
    <nav class="tabs tabs--sub" aria-label="Orden">
        <?php foreach (Song::SORTS as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $sort === $key]) ?>"
                href="<?= e(url('music.php', ['q' => $term, 'genre' => $genre, 'sort' => $key === 'recent' ? null : $key])) ?>"
                <?= $sort === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<form class="community-filters" method="get" action="<?= e(url('music.php')) ?>" role="search" data-music-filters>
    <?php if ($sort !== 'recent'): ?>
        <input type="hidden" name="sort" value="<?= e($sort) ?>">
    <?php endif; ?>
    <div class="search-field community-filters__search">
        <?= icon('search') ?>
        <label class="sr-only" for="music-q">Buscar canciones</label>
        <input id="music-q" type="search" name="q" value="<?= e($term) ?>" maxlength="80" placeholder="Canción, artista o invitado" autocomplete="off">
    </div>
    <div class="select-wrap">
        <?= icon('disc-3') ?>
        <label class="sr-only" for="music-genre">Género</label>
        <select class="select" id="music-genre" name="genre" data-autosubmit>
            <option value="">Todos los géneros</option>
            <?php foreach (Song::GENRES as $key => $label): ?>
                <option value="<?= e($key) ?>" <?= $key === $genre ? 'selected' : '' ?>><?= e($label) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary">Buscar</button>
    <?php if ($filtered): ?>
        <a class="btn btn--ghost" href="<?= e(url('music.php', ['sort' => $sort === 'recent' ? null : $sort])) ?>">Limpiar</a>
    <?php endif; ?>
</form>

<?php if ($unavailable !== []): ?>
    <p class="alert alert--warning" role="status">
        <?= e(implode(' y ', $unavailable)) ?> no <?= count($unavailable) > 1 ? 'respondieron' : 'respondió' ?>: por ahora ves el resto del catálogo.
    </p>
<?php endif; ?>

<?php if ($items === []): ?>
    <?php View::partial('empty-state', $filtered
        ? ['icon' => 'search', 'heading' => 'No encontramos canciones', 'text' => 'Prueba con otras palabras u otro género.']
        : [
            'icon' => 'music', 'heading' => 'No hay canciones para mostrar',
            'text' => 'Busca una canción o un artista.',
            'actionHref' => $isArtist ? url('artist.php') . '#subir' : null, 'actionLabel' => 'Subir canción',
        ]); ?>
<?php else: ?>
    <div class="song-list">
        <?php foreach ($items as $item): ?>
            <?php if ($item['song'] !== null): ?>
                <?php View::partial('song-row', ['song' => $item['song']]); ?>
            <?php else: ?>
                <?php View::partial('catalog-track', ['track' => $item['track']]); ?>
            <?php endif; ?>
        <?php endforeach; ?>
    </div>
    <?php if (in_array('audius', $sources, true) || in_array('freetouse', $sources, true)): ?>
        <p class="music-credit">
            Incluye canciones de Audius (audius.co), que se reproducen desde Audius y pertenecen a sus artistas, y música
            libre de Free To Use (freetouse.com/music), con el crédito del artista junto a cada canción.
        </p>
    <?php endif; ?>
    <?php if ($nextUrl !== null): ?>
        <div class="community-more">
            <a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más canciones</a>
        </div>
    <?php endif; ?>
<?php endif; ?>
