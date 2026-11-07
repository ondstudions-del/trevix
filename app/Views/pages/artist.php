<?php

use Trevix\Controllers\MusicController;
use Trevix\Core\Config;
use Trevix\Core\View;
use Trevix\Models\Song;
use Trevix\Services\MusicService;

/**
 * Panel del artista: enviar canciones a revisión y seguir su estado y sus usos.
 *
 * @var bool        $isArtist
 * @var string      $status   pestaña (MusicController::ARTIST_TABS)
 * @var array       $counts   Song::countsForArtist()
 * @var array       $songs    Song::forArtist()
 * @var string|null $nextUrl
 * @var array       $errors
 * @var array       $old
 * @var array       $viewer
 */
$audio = (array) Config::get('app.uploads.audio');
$limits = (array) Config::get('app.limits');
$maxMb = (int) round($audio['max_bytes'] / 1048576);
$value = static fn (string $key): string => (string) ($old[$key] ?? '');
$emptyTexts = [
    'all'       => 'Cuando envíes tu primera canción, aquí verás su estado y cuántas veces se usa.',
    'published' => 'Tus canciones aprobadas aparecerán aquí.',
    'pending'   => 'No tienes canciones esperando revisión.',
    'rejected'  => 'Ninguna de tus canciones fue rechazada.',
    'withdrawn' => 'No retiraste ninguna canción.',
    'removed'   => 'El equipo no retiró ninguna de tus canciones.',
    'cancelled' => 'No cancelaste ningún envío.',
    'used'      => 'Cuando alguien use una de tus canciones en una publicación, historia o mensaje, aparecerá aquí.',
];
?>
<header class="page-header">
    <div class="page-header__row page-header__row--between">
        <div>
            <h1 class="page-header__title page-header__title--visible">Artista</h1>
            <p class="page-header__subtitle">Publica tu música en TREVIX y sigue cómo la usa la comunidad.</p>
        </div>
        <a class="btn btn--secondary" href="<?= e(url('music.php')) ?>"><?= icon('music') ?> Biblioteca</a>
    </div>
</header>

<?php if (!$isArtist): ?>
    <div class="card artist-notice" role="note">
        <?= icon('info') ?>
        <div>
            <p><strong>Tu cuenta no es de artista musical.</strong> Para subir canciones, en <a href="<?= e(url('edit-profile.php')) ?>#tipo-de-cuenta">Editar perfil</a> elige «Creador de contenido» y la categoría «Artista musical».</p>
            <?php if ($counts['all'] > 0): ?>
                <p class="field__hint">Puedes seguir gestionando las canciones que ya enviaste.</p>
            <?php endif; ?>
        </div>
    </div>
<?php endif; ?>

<?php if ($isArtist || $counts['all'] > 0): ?>
    <section class="artist-stats" aria-label="Resumen">
        <div class="artist-stat"><strong><?= e(compact_number($counts['published'])) ?></strong><span><?= plural($counts['published'], 'Publicada', 'Publicadas') ?></span></div>
        <div class="artist-stat"><strong><?= e(compact_number($counts['pending'])) ?></strong><span>En revisión</span></div>
        <div class="artist-stat"><strong><?= e(compact_number($counts['used'])) ?></strong><span><?= plural($counts['used'], 'Canción usada', 'Canciones usadas') ?></span></div>
        <div class="artist-stat"><strong><?= e(compact_number($counts['uses'])) ?></strong><span><?= plural($counts['uses'], 'Uso en total', 'Usos en total') ?></span></div>
    </section>
<?php endif; ?>

<?php if ($isArtist): ?>
    <section class="card form-card song-upload" id="subir" aria-labelledby="song-upload-title">
        <div>
            <h2 class="form-card__title" id="song-upload-title"><?= icon('upload') ?> Subir una canción</h2>
            <p class="field__hint">El equipo revisa cada canción antes de publicarla en la biblioteca. MP3 o M4A, de <?= (int) $audio['min_seconds'] ?> segundos a <?= intdiv((int) $audio['max_seconds'], 60) ?> minutos y hasta <?= $maxMb ?> MB.</p>
        </div>
        <form class="form" method="post" action="<?= e(url('api/music.php')) ?>" enctype="multipart/form-data" data-song-upload>
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="submit">

            <div class="form__grid">
                <div class="field">
                    <label class="field__label" for="song-title">Título</label>
                    <input class="input" id="song-title" name="title" type="text" maxlength="<?= (int) $limits['song_title'] ?>" required
                        value="<?= e($value('title')) ?>"<?= invalid_attrs($errors, 'title', 'song-title') ?>>
                    <?= field_error($errors, 'title', 'song-title') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="song-featuring">Artistas invitados <span class="field__hint">(opcional)</span></label>
                    <input class="input" id="song-featuring" name="featuring" type="text" maxlength="<?= (int) $limits['song_featuring'] ?>"
                        placeholder="Ej.: Ana Ruiz, DJ Nova" value="<?= e($value('featuring')) ?>"<?= invalid_attrs($errors, 'featuring', 'song-featuring') ?>>
                    <?= field_error($errors, 'featuring', 'song-featuring') ?>
                </div>
            </div>

            <div class="form__grid">
                <div class="field">
                    <label class="field__label" for="song-genre">Género</label>
                    <select class="select" id="song-genre" name="genre" required<?= invalid_attrs($errors, 'genre', 'song-genre') ?>>
                        <option value="">Elige un género</option>
                        <?php foreach (Song::GENRES as $key => $label): ?>
                            <option value="<?= e($key) ?>" <?= $value('genre') === $key ? 'selected' : '' ?>><?= e($label) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <?= field_error($errors, 'genre', 'song-genre') ?>
                </div>
                <div class="field">
                    <span class="field__label">Contenido</span>
                    <label class="checkbox">
                        <input type="checkbox" name="explicit" value="1" <?= $value('explicit') ? 'checked' : '' ?>>
                        <span class="checkbox__box"><?= icon('check') ?></span>
                        <span>Letra explícita</span>
                    </label>
                </div>
            </div>

            <div class="form__grid">
                <div class="field">
                    <span class="field__label" id="song-audio-label">Archivo de audio</span>
                    <label class="song-upload__file">
                        <?= icon('music') ?>
                        <span data-song-audio-name>MP3 o M4A, hasta <?= $maxMb ?> MB</span>
                        <input class="sr-only" id="song-audio" type="file" name="audio" required aria-labelledby="song-audio-label"
                            accept="<?= e(implode(',', array_merge($audio['mimes'], array_map(static fn (string $ext) => '.' . $ext, $audio['extensions'])))) ?>"
                            data-song-audio<?= invalid_attrs($errors, 'audio', 'song-audio') ?>>
                    </label>
                    <?= field_error($errors, 'audio', 'song-audio') ?>
                </div>
                <div class="field">
                    <span class="field__label" id="song-cover-label">Portada <span class="field__hint">(opcional, cuadrada)</span></span>
                    <label class="song-upload__file">
                        <?= icon('image') ?>
                        <span>JPG, PNG o WEBP</span>
                        <input class="sr-only" id="song-cover" type="file" name="cover" aria-labelledby="song-cover-label"
                            accept="<?= e(implode(',', (array) Config::get('app.uploads.image.mimes'))) ?>"<?= invalid_attrs($errors, 'cover', 'song-cover') ?>>
                    </label>
                    <?= field_error($errors, 'cover', 'song-cover') ?>
                </div>
            </div>

            <div class="field">
                <label class="checkbox">
                    <input id="song-rights" type="checkbox" name="rights" value="1" required<?= invalid_attrs($errors, 'rights', 'song-rights') ?>>
                    <span class="checkbox__box"><?= icon('check') ?></span>
                    <span>Confirmo que soy el autor o tengo los derechos para publicar esta canción en TREVIX, y que cualquiera podrá usarla en publicaciones, historias y mensajes.</span>
                </label>
                <?= field_error($errors, 'rights', 'song-rights') ?>
            </div>

            <p class="alert alert--error" role="alert" data-song-error hidden></p>
            <div class="song-upload__progress" data-song-progress-box hidden>
                <span data-song-progress-bar></span>
            </div>

            <div class="form__actions">
                <button type="submit" class="btn btn--primary">Enviar a revisión</button>
            </div>
        </form>
    </section>
<?php endif; ?>

<?php if ($isArtist || $counts['all'] > 0): ?>
    <nav class="tabs artist-tabs" aria-label="Estado de las canciones">
        <?php foreach (MusicController::ARTIST_TABS as $key => $label): ?>
            <?php $n = $counts[$key] ?? 0; ?>
            <?php if ($key !== 'all' && $key !== $status && $n === 0 && in_array($key, ['removed', 'cancelled'], true)) {
                continue;
            } ?>
            <a class="<?= cx('tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('artist.php', ['status' => $key === 'all' ? null : $key])) ?>"
                <?= $status === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?> <span class="tabs__count"><?= (int) $n ?></span></a>
        <?php endforeach; ?>
    </nav>

    <?php if ($songs === []): ?>
        <?php View::partial('empty-state', ['icon' => 'disc-3', 'heading' => 'No hay canciones aquí', 'text' => $emptyTexts[$status]]); ?>
    <?php else: ?>
        <div class="artist-songs">
            <?php foreach ($songs as $s): ?>
                <?php
                $sid = (int) $s['id'];
                $card = [
                    'id' => $sid, 'available' => true, 'title' => $s['title'], 'featuring' => $s['featuring'],
                    'is_explicit' => (bool) $s['is_explicit'], 'duration' => (int) $s['duration_seconds'],
                    'src' => $s['audio_path'], 'cover' => $s['cover_path'],
                    'artist' => ['display_name' => $viewer['display_name']],
                ];
                $action = url('api/music.php');
                ?>
                <article class="artist-song" id="cancion-<?= $sid ?>">
                    <div class="artist-song__head">
                        <span class="<?= cx('song-status', 'song-status--' . $s['status']) ?>"><?= e(Song::STATUSES[$s['status']] ?? $s['status']) ?></span>
                        <span class="artist-song__date">
                            <?= e(Song::GENRES[$s['genre']] ?? 'Otro') ?> · Enviada <?= time_tag((string) $s['created_at']) ?>
                            <?php if ($s['published_at'] !== null && $s['status'] === 'published'): ?> · Publicada <?= time_tag((string) $s['published_at']) ?><?php endif; ?>
                        </span>
                    </div>

                    <?php View::partial('song-chip', ['song' => $card, 'mode' => 'full', 'link' => $s['status'] === 'published']); ?>

                    <?php if (in_array($s['status'], ['rejected', 'removed'], true) && !empty($s['review_note'])): ?>
                        <p class="artist-song__note"><?= icon('triangle-alert') ?> <span><strong>Motivo:</strong> <?= e($s['review_note']) ?></span></p>
                    <?php elseif ($s['status'] === 'published' && !empty($s['review_note'])): ?>
                        <p class="artist-song__note artist-song__note--ok"><?= icon('circle-check') ?> <span><strong>Nota del equipo:</strong> <?= e($s['review_note']) ?></span></p>
                    <?php elseif ($s['status'] === 'pending'): ?>
                        <p class="artist-song__note artist-song__note--info"><?= icon('clock') ?> <span>El equipo la está revisando. Te avisaremos cuando la apruebe o la rechace.</span></p>
                    <?php elseif ($s['status'] === 'withdrawn'): ?>
                        <p class="artist-song__note artist-song__note--info"><?= icon('eye-off') ?> <span>No aparece en la biblioteca y, donde se usó, se muestra «Canción no disponible».</span></p>
                    <?php endif; ?>

                    <dl class="artist-song__uses">
                        <div><dt>Usos en total</dt><dd><?= e(compact_number((int) $s['uses_count'])) ?></dd></div>
                        <div><dt>Publicaciones</dt><dd><?= (int) $s['post_uses'] ?></dd></div>
                        <div><dt>Historias activas</dt><dd><?= (int) $s['story_uses'] ?></dd></div>
                        <div><dt>Mensajes</dt><dd><?= (int) $s['message_uses'] ?></dd></div>
                    </dl>

                    <div class="artist-song__actions">
                        <?php if ($s['status'] === 'published'): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(url('music.php', ['id' => $sid])) ?>"><?= icon('external-link') ?> Ver en la biblioteca</a>
                            <form method="post" action="<?= e($action) ?>"
                                data-confirm="¿Retirar «<?= e($s['title']) ?>»? Saldrá de la biblioteca y, donde se usó, se mostrará «Canción no disponible». Podrás volver a publicarla." data-confirm-label="Retirar">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="withdraw">
                                <input type="hidden" name="song_id" value="<?= $sid ?>">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('archive') ?> Retirar</button>
                            </form>
                        <?php elseif ($s['status'] === 'pending'): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm="¿Cancelar el envío de «<?= e($s['title']) ?>»? El equipo ya no la revisará." data-confirm-label="Cancelar envío">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="cancel">
                                <input type="hidden" name="song_id" value="<?= $sid ?>">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('circle-x') ?> Cancelar envío</button>
                            </form>
                        <?php elseif ($s['status'] === 'withdrawn'): ?>
                            <form method="post" action="<?= e($action) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="republish">
                                <input type="hidden" name="song_id" value="<?= $sid ?>">
                                <button type="submit" class="btn btn--primary btn--sm"><?= icon('undo-2') ?> Volver a publicar</button>
                            </form>
                        <?php endif; ?>
                        <?php if (in_array($s['status'], MusicService::DELETABLE, true)): ?>
                            <form method="post" action="<?= e($action) ?>"
                                data-confirm="¿Eliminar «<?= e($s['title']) ?>» definitivamente? Se borrará el archivo y, donde se usó, se mostrará «Canción no disponible». Esta acción no se puede deshacer." data-confirm-label="Eliminar">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="song_id" value="<?= $sid ?>">
                                <button type="submit" class="btn btn--ghost btn--sm btn--danger-text"><?= icon('trash-2') ?> Eliminar</button>
                            </form>
                        <?php endif; ?>
                    </div>
                </article>
            <?php endforeach; ?>
        </div>
        <?php if ($nextUrl !== null): ?>
            <div class="community-more">
                <a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más canciones</a>
            </div>
        <?php endif; ?>
    <?php endif; ?>
<?php endif; ?>
