<?php

use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Biblioteca de música: canciones de artistas de TREVIX (aprobadas por el equipo) y catálogos externos
 * (Audius y Free To Use), que se pueden escuchar y elegir para publicaciones e historias.
 *
 * @var string      $source  trevix | audius | freetouse
 * @var string      $term
 * @var string|null $genre
 * @var string      $sort    recent | popular
 * @var array       $songs
 * @var array       $tracks        pistas del catálogo externo (MusicCatalog::search)
 * @var string|null $catalogError
 * @var string|null $nextUrl
 * @var bool        $isArtist
 * @var bool        $isPreview
 */
$tracks = $tracks ?? [];
$catalogError = $catalogError ?? null;
$external = $source !== 'trevix';
$filtered = $term !== '' || $genre !== null;
$subtitles = [
    'trevix'    => 'Canciones de artistas de TREVIX para tus publicaciones, historias y mensajes.',
    'audius'    => 'Artistas independientes de Audius. Solo aparecen las canciones que su artista deja escuchar libremente.',
    'freetouse' => 'Música libre de derechos de Free To Use (freetouse.com/music), con el crédito del artista.',
];
?>
<header class="page-header">
    <div class="page-header__row page-header__row--between">
        <div>
            <h1 class="page-header__title page-header__title--visible">Música</h1>
            <p class="page-header__subtitle"><?= e($subtitles[$source]) ?></p>
        </div>
        <?php if ($isArtist): ?>
            <a class="btn btn--primary" href="<?= e(url('artist.php')) ?>#subir"><?= icon('upload') ?> Subir canción</a>
        <?php endif; ?>
    </div>
    <nav class="tabs" aria-label="Catálogo">
        <?php foreach (Song::SOURCES as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $source === $key]) ?>"
                href="<?= e(url('music.php', ['source' => $key === 'trevix' ? null : $key, 'q' => $term])) ?>"
                <?= $source === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>
    <?php if (!$external): ?>
        <nav class="tabs tabs--sub" aria-label="Orden">
            <?php foreach (Song::SORTS as $key => $label): ?>
                <a class="<?= cx('tabs__item', ['is-active' => $sort === $key]) ?>"
                    href="<?= e(url('music.php', ['q' => $term, 'genre' => $genre, 'sort' => $key === 'recent' ? null : $key])) ?>"
                    <?= $sort === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
            <?php endforeach; ?>
        </nav>
    <?php endif; ?>
</header>

<form class="community-filters" method="get" action="<?= e(url('music.php')) ?>" role="search" data-music-filters>
    <?php if ($external): ?>
        <input type="hidden" name="source" value="<?= e($source) ?>">
    <?php elseif ($sort !== 'recent'): ?>
        <input type="hidden" name="sort" value="<?= e($sort) ?>">
    <?php endif; ?>
    <div class="search-field community-filters__search">
        <?= icon('search') ?>
        <label class="sr-only" for="music-q">Buscar canciones</label>
        <input id="music-q" type="search" name="q" value="<?= e($term) ?>" maxlength="80" placeholder="Canción, artista o invitado" autocomplete="off">
    </div>
    <?php if (!$external): ?>
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
    <?php endif; ?>
    <button type="submit" class="btn btn--secondary">Buscar</button>
    <?php if ($filtered): ?>
        <a class="btn btn--ghost" href="<?= e(url('music.php', ['source' => $external ? $source : null, 'sort' => $sort === 'recent' ? null : $sort])) ?>">Limpiar</a>
    <?php endif; ?>
</form>

<?php if ($external): ?>
    <?php if ($catalogError !== null): ?>
        <?php View::partial('empty-state', ['icon' => 'wifi-off', 'heading' => 'Catálogo no disponible', 'text' => $catalogError]); ?>
    <?php elseif ($tracks === []): ?>
        <?php View::partial('empty-state', ['icon' => 'search', 'heading' => 'No encontramos canciones', 'text' => 'Prueba con otras palabras.']); ?>
    <?php else: ?>
        <div class="song-list">
            <?php foreach ($tracks as $track): ?>
                <article class="song-row">
                    <div class="song-chip song-chip--md" data-song-player>
                        <button type="button" class="song-chip__play js-only" data-song-toggle aria-label="Escuchar «<?= e($track['title']) ?>»">
                            <span class="song-chip__icon-play"><?= icon('play') ?></span>
                            <span class="song-chip__icon-pause"><?= icon('pause') ?></span>
                        </button>
                        <span class="song-chip__cover" aria-hidden="true">
                            <?php if ($track['cover_url'] !== null): ?>
                                <img src="<?= e($track['cover_url']) ?>" alt="" loading="lazy">
                            <?php else: ?>
                                <?= icon('music') ?>
                            <?php endif; ?>
                        </span>
                        <span class="song-chip__info">
                            <span class="song-chip__title"><?= e($track['title']) ?></span>
                            <span class="song-chip__artist"><?= e($track['artist']) ?> · <?= e($track['source_label']) ?></span>
                            <span class="song-chip__bar" aria-hidden="true"><span data-song-progress></span></span>
                        </span>
                        <span class="song-chip__time" data-song-time><?= e(sprintf('%d:%02d', intdiv($track['duration'], 60), $track['duration'] % 60)) ?></span>
                        <audio preload="none" src="<?= e($track['audio_url']) ?>" data-start="0" data-end="0"></audio>
                    </div>
                    <p class="song-row__meta"><span><?= e($track['genre_label']) ?></span></p>
                    <div class="song-row__actions">
                        <form method="post" action="<?= e(url('api/music.php')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="import">
                            <input type="hidden" name="source" value="<?= e($track['source']) ?>">
                            <input type="hidden" name="external_id" value="<?= e($track['external_id']) ?>">
                            <button type="submit" class="btn btn--secondary btn--sm"><?= icon('plus') ?> Usar</button>
                        </form>
                        <?php if ($track['source'] === 'audius' && $track['page_url'] !== null): ?>
                            <a class="icon-btn" href="<?= e($track['page_url']) ?>" target="_blank" rel="noopener noreferrer"
                                aria-label="Ver «<?= e($track['title']) ?>» en Audius" data-tooltip="Ver en Audius"><?= icon('external-link') ?></a>
                        <?php endif; ?>
                    </div>
                </article>
            <?php endforeach; ?>
        </div>
        <p class="music-credit">
            <?= $source === 'freetouse'
                ? 'Música de Free To Use (freetouse.com/music). Uso libre con atribución: el crédito del artista se muestra junto a cada canción.'
                : 'Canciones de Audius (audius.co). Se reproducen desde Audius y pertenecen a sus artistas.' ?>
        </p>
        <?php if ($nextUrl !== null): ?>
            <div class="community-more">
                <a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más canciones</a>
            </div>
        <?php endif; ?>
    <?php endif; ?>
<?php elseif ($songs === []): ?>
    <?php View::partial('empty-state', $filtered
        ? ['icon' => 'search', 'heading' => 'No encontramos canciones', 'text' => 'Prueba con otras palabras u otro género.']
        : [
            'icon' => 'music', 'heading' => 'La biblioteca está esperando su primera canción',
            'text' => 'Cuando el equipo apruebe las canciones que envían los artistas, aparecerán aquí. Mientras tanto, explora Audius y Free To Use.',
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
