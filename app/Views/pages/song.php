<?php

use Trevix\Core\Auth;
use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Ficha de una canción de la biblioteca: reproductor completo, accesos para usarla, más canciones del
 * artista y publicaciones que la usan.
 *
 * @var array      $song  Song::findPublished()
 * @var array      $list  ['posts' => [...], 'nextUrl' => ?string]
 * @var array      $more  otras canciones del artista
 * @var array|null $viewer
 */
$artist = $song['artist'];
$external = $song['source'] !== 'trevix';
$canUse = Auth::check();
$songUrl = absolute_url('music.php', ['id' => $song['id']]);
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('music.php')) ?>" aria-label="Volver a la biblioteca" data-tooltip="Biblioteca"><?= icon('chevron-left') ?></a>
        <h1 class="page-header__title page-header__title--visible">Canción</h1>
    </div>
</header>

<section class="card song-hero" aria-labelledby="song-title">
    <div class="song-hero__cover">
        <?php if (!empty($song['cover'])): ?>
            <img src="<?= e(url($song['cover'])) ?>" alt="Portada de «<?= e($song['title']) ?>»">
        <?php else: ?>
            <?= icon('music') ?>
        <?php endif; ?>
    </div>
    <div class="song-hero__info">
        <p class="song-hero__kicker"><?= icon('disc-3') ?> <?= e(Song::GENRES[$song['genre']] ?? 'Otro') ?></p>
        <h2 class="song-hero__title" id="song-title">
            <?= e($song['title']) ?>
            <?php if ($song['is_explicit']): ?><abbr class="song-chip__explicit" title="Contenido explícito">E</abbr><?php endif; ?>
        </h2>
        <p class="song-hero__artist">
            <?php if ($external): ?>
                <span><?= avatar($artist, 'xs') ?> <?= e($artist['display_name']) ?></span>
                <span class="chip chip--muted"><?= e($song['source_label']) ?></span>
            <?php else: ?>
                <a href="<?= e(profile_url($artist)) ?>"><?= avatar($artist, 'xs') ?> <?= e($artist['display_name']) ?></a>
                <?= !empty($artist['is_verified']) ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?>
            <?php endif; ?>
            <?php if (!empty($song['featuring'])): ?>
                <span class="song-hero__feat">feat. <?= e($song['featuring']) ?></span>
            <?php endif; ?>
        </p>
        <p class="song-hero__stats">
            <span><?= icon('clock') ?> <?= e(sprintf('%d:%02d', intdiv($song['duration'], 60), $song['duration'] % 60)) ?></span>
            <span><?= icon('headphones') ?> <?= e(compact_number($song['uses_count'])) ?> <?= plural($song['uses_count'], 'uso', 'usos') ?></span>
            <?php if (!empty($song['published_at'])): ?>
                <span>Publicada <?= time_tag((string) $song['published_at']) ?></span>
            <?php endif; ?>
        </p>
    </div>
    <div class="song-hero__player">
        <?php View::partial('song-chip', ['song' => $song, 'mode' => 'full', 'size' => 'lg']); ?>
    </div>
    <div class="song-hero__actions">
        <?php if ($canUse): ?>
            <button type="button" class="btn btn--primary js-only" data-open-composer
                data-composer-song="<?= e((string) json_encode(song_client($song), JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)) ?>">
                <?= icon('pencil') ?> Usar en publicación
            </button>
            <a class="btn btn--secondary" href="<?= e(url('stories.php', ['new' => 1, 'song' => $song['id']])) ?>"><?= icon('circle-dashed') ?> Usar en historia</a>
        <?php endif; ?>
        <button type="button" class="btn btn--ghost js-only" data-copy-url="<?= e($songUrl) ?>"><?= icon('link') ?> Copiar enlace</button>
        <?php if ($external && !empty($song['external_url'])): ?>
            <a class="btn btn--ghost" href="<?= e($song['external_url']) ?>" target="_blank" rel="noopener noreferrer"><?= icon('external-link') ?> Ver en <?= e($song['source_label']) ?></a>
        <?php endif; ?>
    </div>
    <?php if ($external): ?>
        <p class="song-hero__credit">
            <?php if ($song['source'] === 'freetouse'): ?>
                Música: «<?= e($song['title']) ?>» de <?= e($artist['display_name']) ?> · Fuente: Free To Use (freetouse.com/music). Uso libre con atribución.
            <?php else: ?>
                «<?= e($song['title']) ?>» de <?= e($artist['display_name']) ?> · Se reproduce desde Audius (audius.co), donde el artista la publicó.
            <?php endif; ?>
        </p>
    <?php endif; ?>
</section>

<?php if ($more !== []): ?>
    <section class="song-section" aria-labelledby="song-more-title">
        <h2 class="song-section__title" id="song-more-title">Más de <?= e($artist['display_name']) ?></h2>
        <div class="song-list">
            <?php foreach ($more as $item): ?>
                <?php View::partial('song-row', ['song' => $item]); ?>
            <?php endforeach; ?>
        </div>
    </section>
<?php endif; ?>

<section class="song-section feed" aria-labelledby="song-posts-title">
    <h2 class="song-section__title" id="song-posts-title">Publicaciones con esta canción</h2>
    <?php if ($list['posts'] === []): ?>
        <?php View::partial('empty-state', [
            'icon' => 'music', 'heading' => 'Nadie la usó todavía',
            'text' => $canUse ? 'Sé la primera persona en publicar con esta canción.' : 'Inicia sesión para ver quién la usa.',
        ]); ?>
    <?php else: ?>
        <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => 'Ya viste todas las publicaciones con esta canción.']); ?>
    <?php endif; ?>
</section>
