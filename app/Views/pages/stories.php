<?php

use Trevix\Core\Auth;
use Trevix\Core\View;

/**
 * @var array  $groups     [{user, items: [{id, type, src, body, background, seconds, song, views, seen, created_at}], own?, replyBlocked?}]
 * @var int    $startIndex
 * @var string $exitUrl
 * @var int    $replyMax
 */
$canWrite = Auth::check();
?>
<div class="story-viewer" data-story-viewer data-start="<?= (int) $startIndex ?>" data-exit-url="<?= e($exitUrl) ?>">
    <a class="story-viewer__brand" href="<?= e(url('feed.php')) ?>" aria-label="<?= e(t('TREVIX, volver al inicio')) ?>">
        <?php View::partial('logo', ['size' => 32, 'wordmark' => true]); ?>
    </a>
    <a class="icon-btn story-viewer__close" href="<?= e($exitUrl) ?>" aria-label="<?= e(t('Cerrar historias')) ?>"><?= icon('x') ?></a>
    <div class="story-viewer__flash"><?php View::partial('flash'); ?></div>

    <?php if ($groups === []): ?>
        <div class="story-viewer__empty">
            <?php View::partial('empty-state', [
                'icon' => 'clock', 'heading' => 'No hay historias activas',
                'text' => 'Las historias duran 24 horas. Cuando las personas que sigues publiquen una, aparecerá aquí.',
                'actionHref' => $canWrite ? url('stories.php', ['new' => 1]) : url('feed.php'),
                'actionLabel' => $canWrite ? 'Crear una historia' : 'Volver al inicio',
            ]); ?>
        </div>
    <?php else: ?>
        <div class="story-viewer__stage">
            <button type="button" class="story-viewer__arrow story-viewer__arrow--prev" data-story-prev aria-label="<?= e(t('Historia anterior')) ?>"><?= icon('chevron-left') ?></button>

            <?php foreach ($groups as $i => $group): ?>
                <?php
                $user = $group['user'];
                $own = !empty($group['own']);
                $replyBlocked = $group['replyBlocked'] ?? null;
                $firstUnseen = 0;
                foreach ($group['items'] as $index => $item) {
                    if (!$item['seen']) {
                        $firstUnseen = $index;
                        break;
                    }
                }
                ?>
                <section class="story-card" data-story-group="<?= $i ?>" data-username="<?= e($user['username']) ?>"
                    data-first-unseen="<?= $own ? 0 : $firstUnseen ?>"<?= $own ? ' data-own' : '' ?>
                    aria-label="<?= e(t('Historia de {name}', ['name' => $user['display_name']])) ?>" hidden>
                    <div class="story-card__progress" aria-hidden="true">
                        <?php foreach ($group['items'] as $_): ?>
                            <span class="story-card__bar"><span class="story-card__fill"></span></span>
                        <?php endforeach; ?>
                    </div>

                    <header class="story-card__header">
                        <a class="story-card__user" href="<?= e(profile_url($user)) ?>">
                            <?= avatar($user, 'sm') ?>
                            <strong><?= e($own ? t('Tu historia') : $user['display_name']) ?></strong>
                            <span class="story-card__time" data-story-time></span>
                        </a>
                        <div class="story-card__controls">
                            <button type="button" class="icon-btn icon-btn--sm story-card__mute" data-story-mute aria-label="<?= e(t('Activar sonido')) ?>" aria-pressed="true" hidden>
                                <?= icon('volume-x', 'when-muted') ?><?= icon('volume-2', 'when-sound') ?>
                            </button>
                            <button type="button" class="icon-btn icon-btn--sm story-card__pause" data-story-pause aria-label="<?= e(t('Pausar')) ?>" aria-pressed="false">
                                <?= icon('pause', 'when-playing') ?><?= icon('play', 'when-paused') ?>
                            </button>
                            <?php if (!$own && $canWrite): ?>
                                <a class="icon-btn icon-btn--sm" href="<?= e(url('report.php', ['type' => 'story', 'id' => (int) $group['items'][$firstUnseen]['id']])) ?>"
                                    data-story-report aria-label="<?= e(t('Reportar esta historia')) ?>" data-tooltip="<?= e(t('Reportar')) ?>"><?= icon('flag') ?></a>
                            <?php endif; ?>
                        </div>
                    </header>

                    <div class="story-card__slides">
                        <?php foreach ($group['items'] as $item): ?>
                            <div class="story-slide" data-story-item data-story-id="<?= (int) $item['id'] ?>"
                                data-type="<?= e($item['type']) ?>" data-seconds="<?= (int) $item['seconds'] ?>"
                                data-time="<?= e(time_ago($item['created_at'])) ?>" data-views="<?= (int) $item['views'] ?>"
                                <?= $item['seen'] ? 'data-seen' : '' ?> hidden>
                                <?php $filterClass = !empty($item['filter']) ? ' class="story-filter--' . e($item['filter']) . '"' : ''; ?>
                                <?php if ($item['type'] === 'image'): ?>
                                    <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['body']) ?>" decoding="async"<?= $filterClass ?>>
                                <?php elseif ($item['type'] === 'video'): ?>
                                    <video src="<?= e(url($item['src'])) ?>" preload="metadata" playsinline muted<?= $filterClass ?>></video>
                                <?php else: ?>
                                    <div class="story-slide__text story-bg--<?= e($item['background'] ?: 'violet') ?>">
                                        <p><?= nl2br(e($item['body']), false) ?></p>
                                    </div>
                                <?php endif; ?>
                                <?php if ($item['type'] !== 'text'): ?>
                                    <?php View::partial('story-layers', ['item' => $item, 'own' => $own]); ?>
                                <?php endif; ?>
                                <?php if ($item['type'] !== 'text' && $item['body'] !== ''): ?>
                                    <p class="story-slide__caption"><?= e($item['body']) ?></p>
                                <?php endif; ?>
                                <?php if (!empty($item['song'])): ?>
                                    <?php $song = $item['song']; ?>
                                    <?php if (!empty($song['available'])): ?>
                                        <a class="story-slide__song" href="<?= e(url('music.php', ['id' => $song['id']])) ?>">
                                            <?= icon('music') ?>
                                            <span><strong><?= e($song['title']) ?></strong> · <?= e($song['artist']['display_name']) ?></span>
                                        </a>
                                        <audio preload="metadata" src="<?= e(url($song['src'])) ?>" data-story-audio data-start="<?= (int) $song['start'] ?>"></audio>
                                    <?php else: ?>
                                        <span class="story-slide__song story-slide__song--off"><?= icon('music') ?> <span><?= e(t('Canción no disponible')) ?></span></span>
                                    <?php endif; ?>
                                <?php endif; ?>
                            </div>
                        <?php endforeach; ?>
                    </div>

                    <button type="button" class="story-card__tap story-card__tap--prev" data-story-tap="prev" aria-label="<?= e(t('Anterior')) ?>" tabindex="-1"></button>
                    <button type="button" class="story-card__tap story-card__tap--next" data-story-tap="next" aria-label="<?= e(t('Siguiente')) ?>" tabindex="-1"></button>

                    <?php if ($own): ?>
                        <footer class="story-card__owner">
                            <button type="button" class="story-card__views" data-story-viewers>
                                <?= icon('eye') ?> <span data-story-views>0</span>
                            </button>
                            <a class="icon-btn story-card__add" href="<?= e(url('stories.php', ['new' => 1])) ?>" aria-label="<?= e(t('Crear otra historia')) ?>" data-tooltip="<?= e(t('Nueva historia')) ?>"><?= icon('plus') ?></a>
                            <form method="post" action="<?= e(url('api/stories.php')) ?>" data-story-delete>
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="story_id" value="" data-story-current>
                                <button type="submit" class="icon-btn" aria-label="<?= e(t('Eliminar esta historia')) ?>" data-tooltip="<?= e(t('Eliminar')) ?>"><?= icon('trash-2') ?></button>
                            </form>
                        </footer>
                        <div class="story-viewers" data-story-viewers-panel hidden>
                            <header class="story-viewers__head">
                                <h2><?= icon('eye') ?> <span data-story-viewers-title><?= e(t('Vistas')) ?></span></h2>
                                <button type="button" class="icon-btn icon-btn--sm" data-story-viewers-close aria-label="<?= e(t('Cerrar')) ?>"><?= icon('x') ?></button>
                            </header>
                            <ul class="story-viewers__list" data-story-viewers-list></ul>
                        </div>
                    <?php elseif ($canWrite): ?>
                        <form class="story-card__reply" method="post" action="<?= e(url('api/stories.php')) ?>" data-story-reply-form>
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="reply">
                            <input type="hidden" name="story_id" value="" data-story-current>
                            <label class="sr-only" for="story-reply-<?= $i ?>"><?= e(t('Responder')) ?></label>
                            <?php if ($replyBlocked === null): ?>
                                <input id="story-reply-<?= $i ?>" type="text" name="body" maxlength="<?= (int) $replyMax ?>" required autocomplete="off"
                                    placeholder="<?= e(t('Responder a {name}…', ['name' => explode(' ', $user['display_name'])[0]])) ?>" data-story-reply>
                                <button type="submit" class="icon-btn" aria-label="<?= e(t('Enviar respuesta')) ?>"><?= icon('send') ?></button>
                            <?php else: ?>
                                <input id="story-reply-<?= $i ?>" type="text" disabled placeholder="<?= e($replyBlocked) ?>">
                            <?php endif; ?>
                        </form>
                    <?php endif; ?>
                </section>
            <?php endforeach; ?>

            <button type="button" class="story-viewer__arrow story-viewer__arrow--next" data-story-next aria-label="<?= e(t('Historia siguiente')) ?>"><?= icon('chevron-right') ?></button>
        </div>
    <?php endif; ?>
</div>
<?php View::partial('confirm-dialog'); ?>
<script src="<?= e(asset('js/stories.js')) ?>" defer></script>
