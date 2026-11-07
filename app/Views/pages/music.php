<?php

use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Biblioteca de música: canciones publicadas por artistas y aprobadas por el equipo.
 *
 * @var string      $term
 * @var string|null $genre
 * @var string      $sort    recent | popular
 * @var array       $songs
 * @var string|null $nextUrl
 * @var bool        $isArtist
 * @var bool        $isPreview
 */
$filtered = $term !== '' || $genre !== null;
?>
<header class="page-header">
    <div class="page-header__row page-header__row--between">
        <div>
            <h1 class="page-header__title page-header__title--visible">Música</h1>
            <p class="page-header__subtitle">Canciones de artistas de TREVIX para tus publicaciones, historias y mensajes.</p>
        </div>
        <?php if ($isArtist): ?>
            <a class="btn btn--primary" href="<?= e(url('artist.php')) ?>#subir"><?= icon('upload') ?> Subir canción</a>
        <?php endif; ?>
    </div>
    <nav class="tabs" aria-label="Orden">
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

<?php if ($songs === []): ?>
    <?php View::partial('empty-state', $filtered
        ? ['icon' => 'search', 'heading' => 'No encontramos canciones', 'text' => 'Prueba con otras palabras u otro género.']
        : [
            'icon' => 'music', 'heading' => 'La biblioteca está esperando su primera canción',
            'text' => 'Cuando el equipo apruebe las canciones que envían los artistas, aparecerán aquí.',
            'actionHref' => $isArtist ? url('artist.php') . '#subir' : null, 'actionLabel' => 'Subir canción',
        ]); ?>
<?php else: ?>
    <div class="song-list">
        <?php foreach ($songs as $song): ?>
            <?php View::partial('song-row', ['song' => $song]); ?>
        <?php endforeach; ?>
    </div>
    <?php if ($nextUrl !== null): ?>
        <div class="community-more">
            <a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más canciones</a>
        </div>
    <?php endif; ?>
<?php endif; ?>
