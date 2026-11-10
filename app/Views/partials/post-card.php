<?php

use Trevix\Core\Auth;
use Trevix\Core\View;

/**
 * Tarjeta de publicación con la estructura que devuelve Post::feed().
 * Me gusta y guardar son formularios reales: funcionan sin JavaScript y posts.js los envía con fetch.
 *
 * @var array      $post
 * @var array|null $viewer
 */
$author = $post['user'];
$media = $post['media'] ?? [];
$mediaCount = count($media);
$isThread = ($post['format'] ?? 'post') === 'thread';
$isOwn = !empty($viewer) && (int) $viewer['id'] === (int) $author['id'];
$postId = (int) $post['id'];
$authorId = 'post-' . $postId . '-author';
$postUrl = url('post.php', ['id' => $postId]);
$canInteract = Auth::check();

$song = $post['song'] ?? null;
$gif = $post['gif'] ?? null;
$event = $post['event'] ?? null;
$lifeEvent = $post['life_event'] ?? null;
$location = $post['location'] ?? null;
$background = $isThread ? ($post['background'] ?? null) : null;
$isRepost = ($post['body'] ?? '') === '' && $mediaCount === 0 && $song === null && $gif === null && $event === null && $lifeEvent === null
    && (!empty($post['shared']) || !empty($post['shared_missing']));
$canFeature = !empty($viewer) && Auth::check() && \Trevix\Services\Moderation::isAdmin($viewer)
    && ($post['visibility'] ?? 'public') === 'public' && ($post['community']['visibility'] ?? 'public') === 'public';
// Al compartir un "compartido" se comparte la publicación original.
$shareTarget = $isRepost ? ($post['shared'] ?? null) : $post;
$privateCommunity = ($shareTarget['community']['visibility'] ?? 'public') === 'private';
$canShare = $canInteract && $shareTarget !== null && ($shareTarget['visibility'] ?? 'public') === 'public' && !$privateCommunity;
$shareHint = match (true) {
    $shareTarget === null => 'La publicación original ya no está disponible',
    $privateCommunity     => 'Las publicaciones de comunidades privadas no se pueden compartir',
    default               => 'Solo se pueden compartir publicaciones públicas',
};
// La página de la comunidad marca las publicaciones que quien mira puede moderar.
$canModerate = $canInteract && !$isOwn && !empty($post['community']['can_moderate']);
$visibilityIcons = ['followers' => ['users', 'Visible para seguidores'], 'private' => ['lock', 'Solo tú puedes verla']];
$loginHint = 'data-tooltip="Inicia sesión para interactuar"';
?>
<article class="<?= cx('post', ['post--thread' => $isThread, 'post--featured' => !empty($post['featured'])]) ?>" aria-labelledby="<?= $authorId ?>" data-post-id="<?= $postId ?>">
    <?php if (!empty($post['featured'])): ?>
        <p class="post__context post__context--featured"><?= icon('star') ?> Destacado</p>
    <?php endif; ?>
    <?php if ($isRepost): ?>
        <p class="post__context"><?= icon('repeat-2') ?> <?= e($isOwn ? 'Compartiste' : $author['display_name'] . ' compartió') ?></p>
    <?php endif; ?>
    <header class="post__header">
        <a class="post__avatar" href="<?= e(profile_url($author)) ?>" tabindex="-1" aria-hidden="true"><?= avatar($author, 'md') ?></a>
        <div class="post__meta">
            <div class="post__byline">
                <a class="post__author" id="<?= $authorId ?>" href="<?= e(profile_url($author)) ?>"><?= e($author['display_name']) ?></a>
                <?= !empty($author['is_verified']) ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?>
                <span class="post__handle">@<?= e($author['username']) ?></span>
                <span class="post__dot" aria-hidden="true">·</span>
                <a class="post__time" href="<?= e($postUrl) ?>"><?= time_tag($post['created_at']) ?></a>
                <?php if (!empty($post['is_edited'])): ?>
                    <span class="post__edited">· editado</span>
                <?php endif; ?>
                <?php if (isset($visibilityIcons[$post['visibility'] ?? 'public'])): ?>
                    <?php [$visIcon, $visLabel] = $visibilityIcons[$post['visibility']]; ?>
                    <span class="post__visibility" data-tooltip="<?= e($visLabel) ?>"><?= icon($visIcon, '', $visLabel) ?></span>
                <?php endif; ?>
            </div>
            <?php if (!empty($post['community'])): ?>
                <a class="post__community" href="<?= e(community_url($post['community'])) ?>">
                    <?= icon(($post['community']['visibility'] ?? 'public') === 'private' ? 'lock' : 'users-round') ?> <?= e($post['community']['name']) ?>
                </a>
            <?php elseif ($isThread): ?>
                <span class="post__format"><?= icon('messages-square') ?> Hilo</span>
            <?php endif; ?>
            <?php if ($location !== null): ?>
                <?php if ($location['lat'] !== null && $location['lng'] !== null): ?>
                    <a class="post__location" href="<?= e('https://www.openstreetmap.org/?mlat=' . $location['lat'] . '&mlon=' . $location['lng'] . '#map=13/' . $location['lat'] . '/' . $location['lng']) ?>"
                        target="_blank" rel="noopener noreferrer"><?= icon('map-pin') ?> <?= e($location['name']) ?></a>
                <?php else: ?>
                    <span class="post__location"><?= icon('map-pin') ?> <?= e($location['name']) ?></span>
                <?php endif; ?>
            <?php endif; ?>
        </div>

        <div class="dropdown" data-dropdown>
            <button type="button" class="icon-btn icon-btn--sm" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false" aria-label="Opciones de la publicación">
                <?= icon('ellipsis') ?>
            </button>
            <div class="dropdown__menu" role="menu" hidden>
                <?php if ($isOwn && $canInteract): ?>
                    <a class="dropdown__item" role="menuitem" href="<?= e(url('edit-post.php', ['id' => $postId])) ?>"><?= icon('pencil') ?> Editar publicación</a>
                    <form method="post" action="<?= e(url('api/posts.php')) ?>" data-confirm="¿Eliminar esta publicación? Se borrarán también sus comentarios y archivos. Esta acción no se puede deshacer." data-confirm-label="Eliminar">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="post_id" value="<?= $postId ?>">
                        <button type="submit" class="dropdown__item dropdown__item--danger" role="menuitem"><?= icon('trash-2') ?> Eliminar</button>
                    </form>
                <?php elseif (!$isOwn): ?>
                    <a class="dropdown__item" role="menuitem" href="<?= e(profile_url($author)) ?>"><?= icon('user') ?> Ver perfil de @<?= e($author['username']) ?></a>
                    <?php if ($canInteract): ?>
                        <?php $followsAuthor = !empty($author['viewer_follows']); ?>
                        <form method="post" action="<?= e(url('api/follows.php')) ?>" data-follow-menu
                            data-user-id="<?= (int) $author['id'] ?>" data-username="<?= e($author['username']) ?>" data-private="<?= !empty($author['is_private']) ? '1' : '0' ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="<?= $followsAuthor ? 'unfollow' : 'follow' ?>">
                            <input type="hidden" name="user_id" value="<?= (int) $author['id'] ?>">
                            <button type="submit" class="dropdown__item" role="menuitem">
                                <span class="dropdown__icon" data-follow-icon="none"<?= $followsAuthor ? ' hidden' : '' ?>><?= icon('user-plus') ?></span>
                                <span class="dropdown__icon" data-follow-icon="active"<?= $followsAuthor ? '' : ' hidden' ?>><?= icon('user-minus') ?></span>
                                <span data-follow-label><?= $followsAuthor ? 'Dejar de seguir' : 'Seguir' ?> a @<?= e($author['username']) ?></span>
                            </button>
                        </form>
                    <?php endif; ?>
                    <?php if ($canModerate): ?>
                        <form method="post" action="<?= e(url('api/communities.php')) ?>"
                            data-confirm="¿Quitar esta publicación de <?= e($post['community']['name']) ?>? No se borra: vuelve al perfil de su autor." data-confirm-label="Quitar">
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="remove_post">
                            <input type="hidden" name="community_id" value="<?= (int) $post['community']['id'] ?>">
                            <input type="hidden" name="post_id" value="<?= $postId ?>">
                            <button type="submit" class="dropdown__item dropdown__item--danger" role="menuitem"><?= icon('shield') ?> Quitar de la comunidad</button>
                        </form>
                    <?php endif; ?>
                    <a class="dropdown__item dropdown__item--danger" role="menuitem" href="<?= e(url('report.php', ['type' => 'post', 'id' => $postId])) ?>"
                        data-report="post" data-report-id="<?= $postId ?>" data-report-label="la publicación de @<?= e($author['username']) ?>"><?= icon('flag') ?> Reportar</a>
                <?php endif; ?>
                <?php if (($post['visibility'] ?? 'public') === 'public' && ($post['community']['visibility'] ?? 'public') === 'public'): ?>
                    <button type="button" class="dropdown__item js-only" role="menuitem" data-share-out="<?= e($postUrl) ?>"
                        data-share-title="<?= e(trim($author['display_name'] . ' en TREVIX: ' . mb_strimwidth((string) ($post['body'] ?? ''), 0, 120, '…'), ': ')) ?>"><?= icon('share-2') ?> Compartir en otras redes</button>
                <?php endif; ?>
                <?php if ($canFeature): ?>
                    <form method="post" action="<?= e(url('admin/content.php')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="id" value="<?= $postId ?>">
                        <input type="hidden" name="action" value="<?= !empty($post['featured']) ? 'unfeature' : 'feature' ?>">
                        <button type="submit" class="dropdown__item" role="menuitem"><?= icon('star') ?> <?= !empty($post['featured']) ? 'Quitar de destacadas' : 'Destacar publicación' ?></button>
                    </form>
                <?php endif; ?>
                <button type="button" class="dropdown__item" role="menuitem" data-copy-url="<?= e($postUrl) ?>"><?= icon('link') ?> Copiar enlace</button>
                <?php if (($post['body'] ?? '') !== ''): ?>
                    <button type="button" class="dropdown__item" role="menuitem" data-copy-text="<?= e($post['body']) ?>"><?= icon('copy') ?> Copiar texto</button>
                <?php endif; ?>
            </div>
        </div>
    </header>

    <?php if ($lifeEvent !== null): ?>
        <div class="post-life">
            <span class="post-life__icon"><?= icon($lifeEvent['icon']) ?></span>
            <strong class="post-life__label"><?= e($lifeEvent['label']) ?></strong>
        </div>
    <?php endif; ?>

    <?php if (($post['body'] ?? '') !== ''): ?>
        <?php if ($background !== null): ?>
            <div class="post__body post__body--bg story-bg--<?= e($background) ?>"><?= format_post_body($post['body']) ?></div>
        <?php else: ?>
            <div class="post__body" data-collapsible><?= format_post_body($post['body']) ?></div>
        <?php endif; ?>
    <?php endif; ?>

    <?php if ($gif !== null): ?>
        <div class="post__gif"><?php View::partial('gif', ['gif' => $gif]); ?></div>
    <?php endif; ?>

    <?php if ($event !== null): ?>
        <?php View::partial('event-card', ['event' => $event]); ?>
    <?php endif; ?>

    <?php if ($mediaCount > 0): ?>
        <div class="post__media post__media--n<?= min($mediaCount, 4) ?>" data-lightbox-group>
            <?php foreach (array_slice($media, 0, 4) as $i => $item): ?>
                <figure class="post__media-item">
                    <?php if ($item['type'] === 'video'): ?>
                        <video src="<?= e(url($item['src'])) ?>"<?= !empty($item['poster']) ? ' poster="' . e(url($item['poster'])) . '"' : '' ?> controls preload="metadata" playsinline></video>
                    <?php else: ?>
                        <button type="button" class="post__media-open" data-lightbox-index="<?= $i ?>" aria-label="Ver imagen <?= $i + 1 ?> de <?= $mediaCount ?>">
                            <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['alt'] ?? '') ?>" loading="lazy" decoding="async">
                            <?php if ($i === 3 && $mediaCount > 4): ?>
                                <span class="post__media-more">+<?= $mediaCount - 4 ?></span>
                            <?php endif; ?>
                        </button>
                    <?php endif; ?>
                </figure>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>

    <?php if ($song !== null): ?>
        <div class="post__song"><?php View::partial('song-chip', ['song' => $song, 'mode' => 'clip']); ?></div>
    <?php endif; ?>

    <?php if (!empty($post['shared'])): ?>
        <?php View::partial('post-embed', ['post' => $post['shared']]); ?>
    <?php elseif (!empty($post['shared_missing'])): ?>
        <div class="post-embed post-embed--missing"><?= icon('eye-off') ?> La publicación original ya no está disponible.</div>
    <?php endif; ?>

    <footer class="post__actions">
        <?php $liked = !empty($post['viewer_liked']); ?>
        <form class="post__action-form" method="post" action="<?= e(url('api/likes.php')) ?>" data-toggle-form="like">
            <?= csrf_field() ?>
            <input type="hidden" name="post_id" value="<?= $postId ?>">
            <button type="submit" class="<?= cx('action', 'action--like', ['is-active' => $liked]) ?>" aria-pressed="<?= $liked ? 'true' : 'false' ?>"
                aria-label="Me gusta" <?= $canInteract ? '' : 'disabled ' . $loginHint ?>>
                <?= icon('heart') ?>
                <span data-count><?= e(compact_number((int) $post['likes_count'])) ?></span>
            </button>
        </form>

        <a class="action action--comment" href="<?= e($postUrl) ?>#comentarios" aria-label="Comentarios (<?= (int) $post['comments_count'] ?>)">
            <?= icon('message-circle') ?>
            <span><?= e(compact_number((int) $post['comments_count'])) ?></span>
        </a>

        <?php if ($canShare): ?>
            <button type="button" class="action action--share" aria-label="Compartir (<?= (int) $post['shares_count'] ?>)"
                data-share-post="<?= (int) $shareTarget['id'] ?>"
                data-share-author="<?= e($shareTarget['user']['display_name'] . ' · @' . $shareTarget['user']['username']) ?>"
                data-share-text="<?= e(mb_strimwidth((string) ($shareTarget['body'] ?? ''), 0, 180, '…')) ?>">
                <?= icon('repeat-2') ?>
                <span><?= e(compact_number((int) $post['shares_count'])) ?></span>
            </button>
        <?php else: ?>
            <button type="button" class="action action--share" disabled <?= $canInteract ? 'data-tooltip="' . e($shareHint) . '"' : $loginHint ?>
                aria-label="Compartir (<?= (int) $post['shares_count'] ?>)">
                <?= icon('repeat-2') ?>
                <span><?= e(compact_number((int) $post['shares_count'])) ?></span>
            </button>
        <?php endif; ?>

        <?php $saved = !empty($post['viewer_saved']); ?>
        <form class="post__action-form" method="post" action="<?= e(url('api/saves.php')) ?>" data-toggle-form="save">
            <?= csrf_field() ?>
            <input type="hidden" name="post_id" value="<?= $postId ?>">
            <button type="submit" class="<?= cx('action', 'action--save', ['is-active' => $saved]) ?>" aria-pressed="<?= $saved ? 'true' : 'false' ?>"
                aria-label="Guardar publicación" <?= $canInteract ? '' : 'disabled ' . $loginHint ?>>
                <?= icon('bookmark') ?>
            </button>
        </form>
    </footer>

    <?php if (!empty($post['replies'])): ?>
        <div class="post__replies">
            <?php foreach ($post['replies'] as $reply): ?>
                <div class="reply">
                    <a href="<?= e(profile_url($reply['user'])) ?>" tabindex="-1" aria-hidden="true"><?= avatar($reply['user'], 'sm') ?></a>
                    <div class="reply__content">
                        <div class="reply__byline">
                            <a class="reply__author" href="<?= e(profile_url($reply['user'])) ?>"><?= e($reply['user']['display_name']) ?></a>
                            <?= time_tag($reply['created_at']) ?>
                        </div>
                        <p class="reply__body"><?= format_post_body($reply['body']) ?></p>
                    </div>
                </div>
            <?php endforeach; ?>
            <a class="post__all-replies" href="<?= e($postUrl) ?>#comentarios">
                Ver los <?= e(compact_number((int) $post['comments_count'])) ?> comentarios
            </a>
        </div>
    <?php endif; ?>
</article>
