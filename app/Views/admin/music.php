<?php

use Trevix\Controllers\Admin\MusicController;
use Trevix\Core\View;
use Trevix\Models\Song;

/**
 * Revisión de canciones: escuchar, aprobar o rechazar las pendientes y retirar o restaurar las publicadas.
 *
 * @var string      $status
 * @var string      $q
 * @var array       $counts  Song::adminCounts()
 * @var array       $songs   Song::adminList()
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/music.php');
$emptyTexts = [
    'pending'   => t('No hay canciones esperando revisión.'),
    'published' => t('Todavía no hay canciones publicadas.'),
    'rejected'  => t('No hay canciones rechazadas.'),
    'removed'   => t('No hay canciones retiradas por moderación.'),
    'withdrawn' => t('Ningún artista retiró sus canciones.'),
];
?>
<nav class="admin-tabs" aria-label="<?= e(t('Estado de las canciones')) ?>">
    <?php foreach (MusicController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/music.php', ['status' => $key === 'pending' ? null : $key])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e(t($label)) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<form class="admin-search" method="get" action="<?= e($action) ?>" role="search">
    <?php if ($status !== 'pending'): ?>
        <input type="hidden" name="status" value="<?= e($status) ?>">
    <?php endif; ?>
    <div class="input-wrap">
        <?= icon('search') ?>
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100" placeholder="<?= e(t('Título, invitados o @artista')) ?>" aria-label="<?= e(t('Buscar canciones')) ?>">
    </div>
    <button type="submit" class="btn btn--secondary"><?= e(t('Buscar')) ?></button>
</form>

<section class="panel">
    <?php if ($songs === []): ?>
        <div class="panel__empty">
            <?= icon('music') ?>
            <p><?= e($q !== '' ? t('No hay canciones con esa búsqueda.') : $emptyTexts[$status]) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($songs as $s): ?>
                <?php
                $sid = (int) $s['id'];
                $duration = (int) $s['duration_seconds'];
                ?>
                <li class="content-row song-review" id="cancion-<?= $sid ?>">
                    <div class="song-review__cover" aria-hidden="true">
                        <?php if (!empty($s['cover_path'])): ?>
                            <img src="<?= e(url($s['cover_path'])) ?>" alt="" loading="lazy">
                        <?php else: ?>
                            <?= icon('music') ?>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <strong><?= e($s['title']) ?></strong>
                            <?php if ((int) $s['is_explicit'] === 1): ?><span class="chip chip--muted" title="<?= e(t('Contenido explícito')) ?>"><?= e(t('Explícita')) ?></span><?php endif; ?>
                            <span class="chip chip--muted"><?= e(t(Song::GENRES[$s['genre']] ?? 'Otro')) ?></span>
                            <?php if ($s['artist_id'] === null): ?>
                                <span class="chip chip--muted"><?= e(Song::SOURCES[$s['source']] ?? $s['source']) ?></span>
                            <?php elseif ($s['artist_status'] !== 'active'): ?>
                                <span class="chip chip--danger"><?= e(t('Cuenta no activa')) ?></span>
                            <?php endif; ?>
                        </p>
                        <p class="content-row__muted">
                            <?php if ($s['artist_id'] === null): ?>
                                <?= e((string) $s['external_artist']) ?>
                                <?php if (!empty($s['external_url'])): ?>
                                    · <a href="<?= e($s['external_url']) ?>" target="_blank" rel="noopener noreferrer"><?= e(t('Ver en {source}', ['source' => Song::SOURCES[$s['source']] ?? ''])) ?></a>
                                <?php endif; ?>
                                · <?= e(sprintf('%d:%02d', intdiv($duration, 60), $duration % 60)) ?>
                                · <?= e(t('tomada del catálogo')) ?> <?= time_tag((string) $s['created_at']) ?>
                            <?php else: ?>
                                <?= avatar($s, 'xs') ?>
                                <a href="<?= e(url('admin/users.php', ['id' => $s['artist_id']])) ?>"><?= e($s['display_name']) ?> (@<?= e($s['username']) ?>)</a>
                                <?php if (!empty($s['featuring'])): ?> · feat. <?= e($s['featuring']) ?><?php endif; ?>
                                · <?= e(sprintf('%d:%02d', intdiv($duration, 60), $duration % 60)) ?>
                                · <?= e(strtoupper(pathinfo((string) $s['audio_path'], PATHINFO_EXTENSION))) ?>, <?= e(number_format((int) $s['size_bytes'] / 1048576, 1, ',', '.')) ?> MB
                                · <?= e(t('enviada')) ?> <?= time_tag((string) $s['created_at']) ?>
                            <?php endif; ?>
                            <?php if ((int) $s['uses_count'] > 0): ?> · <?= compact_number((int) $s['uses_count']) ?> <?= plural((int) $s['uses_count'], 'uso', 'usos') ?><?php endif; ?>
                        </p>
                        <audio class="song-review__audio" controls preload="none" src="<?= e(url($s['audio_path'])) ?>">
                            <a href="<?= e(url($s['audio_path'])) ?>"><?= e(t('Descargar el audio')) ?></a>
                        </audio>
                        <?php if ($s['reviewed_at'] !== null): ?>
                            <p class="content-row__muted">
                                <?= e(t('Revisada')) ?> <?= time_tag((string) $s['reviewed_at']) ?><?= $s['reviewer_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $s['reviewer_username']])) : '' ?>
                                <?php if (!empty($s['review_note'])): ?> · «<?= e($s['review_note']) ?>»<?php endif; ?>
                            </p>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($s['status'] === 'published'): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(url('music.php', ['id' => $sid])) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> <?= e(t('Ver')) ?></a>
                        <?php endif; ?>
                        <?php if ($s['status'] === 'pending'): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('circle-check') ?> <?= e(t('Aprobar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="approve">
                                        <label class="field__label" for="approve-<?= $sid ?>"><?= e(t('Nota para el artista')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                                        <input class="input" id="approve-<?= $sid ?>" name="note" maxlength="255">
                                        <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('circle-check') ?> <?= e(t('Publicar en la biblioteca')) ?></button>
                                    </form>
                                </div>
                            </details>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Rechazar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="reject">
                                        <label class="field__label" for="reject-<?= $sid ?>"><?= e(t('Motivo (lo verá el artista)')) ?></label>
                                        <input class="input" id="reject-<?= $sid ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('circle-x') ?> <?= e(t('Rechazar canción')) ?></button>
                                    </form>
                                </div>
                            </details>
                        <?php elseif (in_array($s['status'], ['published', 'withdrawn'], true)): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('archive') ?> <?= e(t('Retirar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>"
                                        data-confirm="<?= e(t('¿Retirar «{title}»? Saldrá de la biblioteca y, donde se usó, se mostrará «Canción no disponible». El artista no podrá volver a publicarla.', ['title' => $s['title']])) ?>" data-confirm-label="<?= e(t('Retirar')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="remove">
                                        <label class="field__label" for="remove-<?= $sid ?>"><?= e(t('Motivo (lo verá el artista)')) ?></label>
                                        <input class="input" id="remove-<?= $sid ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('archive') ?> <?= e(t('Retirar canción')) ?></button>
                                    </form>
                                </div>
                            </details>
                        <?php elseif ($s['status'] === 'removed'): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Restaurar «{title}» en la biblioteca?', ['title' => $s['title']])) ?>" data-confirm-label="<?= e(t('Restaurar')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $sid ?>">
                                <input type="hidden" name="action" value="restore">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('undo-2') ?> <?= e(t('Restaurar')) ?></button>
                            </form>
                        <?php endif; ?>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
