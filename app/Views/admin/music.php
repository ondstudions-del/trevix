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
    'pending'   => 'No hay canciones esperando revisión.',
    'published' => 'Todavía no hay canciones publicadas.',
    'rejected'  => 'No hay canciones rechazadas.',
    'removed'   => 'No hay canciones retiradas por moderación.',
    'withdrawn' => 'Ningún artista retiró sus canciones.',
];
?>
<nav class="admin-tabs" aria-label="Estado de las canciones">
    <?php foreach (MusicController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/music.php', ['status' => $key === 'pending' ? null : $key])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e($label) ?>
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
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100" placeholder="Título, invitados o @artista" aria-label="Buscar canciones">
    </div>
    <button type="submit" class="btn btn--secondary">Buscar</button>
</form>

<section class="panel">
    <?php if ($songs === []): ?>
        <div class="panel__empty">
            <?= icon('music') ?>
            <p><?= e($q !== '' ? 'No hay canciones con esa búsqueda.' : $emptyTexts[$status]) ?></p>
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
                            <?php if ((int) $s['is_explicit'] === 1): ?><span class="chip chip--muted" title="Contenido explícito">Explícita</span><?php endif; ?>
                            <span class="chip chip--muted"><?= e(Song::GENRES[$s['genre']] ?? 'Otro') ?></span>
                            <?php if ($s['artist_status'] !== 'active'): ?><span class="chip chip--danger">Cuenta no activa</span><?php endif; ?>
                        </p>
                        <p class="content-row__muted">
                            <?= avatar($s, 'xs') ?>
                            <a href="<?= e(url('admin/users.php', ['id' => $s['artist_id']])) ?>"><?= e($s['display_name']) ?> (@<?= e($s['username']) ?>)</a>
                            <?php if (!empty($s['featuring'])): ?> · feat. <?= e($s['featuring']) ?><?php endif; ?>
                            · <?= e(sprintf('%d:%02d', intdiv($duration, 60), $duration % 60)) ?>
                            · <?= e(strtoupper(pathinfo((string) $s['audio_path'], PATHINFO_EXTENSION))) ?>, <?= e(number_format((int) $s['size_bytes'] / 1048576, 1, ',', '.')) ?> MB
                            · enviada <?= time_tag((string) $s['created_at']) ?>
                            <?php if ((int) $s['uses_count'] > 0): ?> · <?= compact_number((int) $s['uses_count']) ?> <?= plural((int) $s['uses_count'], 'uso', 'usos') ?><?php endif; ?>
                        </p>
                        <audio class="song-review__audio" controls preload="none" src="<?= e(url($s['audio_path'])) ?>">
                            <a href="<?= e(url($s['audio_path'])) ?>">Descargar el audio</a>
                        </audio>
                        <?php if ($s['reviewed_at'] !== null): ?>
                            <p class="content-row__muted">
                                Revisada <?= time_tag((string) $s['reviewed_at']) ?><?= $s['reviewer_username'] !== null ? ' por @' . e($s['reviewer_username']) : '' ?>
                                <?php if (!empty($s['review_note'])): ?> · «<?= e($s['review_note']) ?>»<?php endif; ?>
                            </p>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($s['status'] === 'published'): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(url('music.php', ['id' => $sid])) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> Ver</a>
                        <?php endif; ?>
                        <?php if ($s['status'] === 'pending'): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('circle-check') ?> Aprobar</summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="approve">
                                        <label class="field__label" for="approve-<?= $sid ?>">Nota para el artista <span class="field__hint">(opcional)</span></label>
                                        <input class="input" id="approve-<?= $sid ?>" name="note" maxlength="255">
                                        <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('circle-check') ?> Publicar en la biblioteca</button>
                                    </form>
                                </div>
                            </details>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> Rechazar</summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="reject">
                                        <label class="field__label" for="reject-<?= $sid ?>">Motivo (lo verá el artista)</label>
                                        <input class="input" id="reject-<?= $sid ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('circle-x') ?> Rechazar canción</button>
                                    </form>
                                </div>
                            </details>
                        <?php elseif (in_array($s['status'], ['published', 'withdrawn'], true)): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('archive') ?> Retirar</summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>"
                                        data-confirm="¿Retirar «<?= e($s['title']) ?>»? Saldrá de la biblioteca y, donde se usó, se mostrará «Canción no disponible». El artista no podrá volver a publicarla." data-confirm-label="Retirar">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $sid ?>">
                                        <input type="hidden" name="action" value="remove">
                                        <label class="field__label" for="remove-<?= $sid ?>">Motivo (lo verá el artista)</label>
                                        <input class="input" id="remove-<?= $sid ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('archive') ?> Retirar canción</button>
                                    </form>
                                </div>
                            </details>
                        <?php elseif ($s['status'] === 'removed'): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm="¿Restaurar «<?= e($s['title']) ?>» en la biblioteca?" data-confirm-label="Restaurar">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $sid ?>">
                                <input type="hidden" name="action" value="restore">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('undo-2') ?> Restaurar</button>
                            </form>
                        <?php endif; ?>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
