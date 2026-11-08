<?php

use Trevix\Core\Auth;
use Trevix\Core\View;
use Trevix\Models\User;

/**
 * @var array       $profile
 * @var bool        $isOwn
 * @var bool        $isBlocked  quien mira bloqueó esta cuenta
 * @var bool        $canView
 * @var string      $tab
 * @var array       $tabs
 * @var array       $list ['posts' => [...], 'nextUrl' => ?string]
 * @var array       $people
 * @var string|null $peopleNext
 * @var array       $songs     canciones publicadas (pestaña Música)
 * @var string|null $songsNext
 * @var array|null  $viewer
 * @var array|null  $storyRing ['unseen' => bool] si la cuenta tiene historias visibles
 */
$cover = !empty($profile['cover_path'])
    ? url($profile['cover_path'])
    : (!empty($profile['cover_art']) ? url('assets/img/demo/' . $profile['cover_art'] . '.svg') : null);
$relation = relation_of($profile);
$joined = strtotime($profile['created_at']) ?: time();
$tabUrl = static fn (string $key) => url('profile.php', ['u' => $profile['username'], 'tab' => $key === 'posts' ? null : $key]);
$canAct = Auth::check() && !$isOwn;
?>
<section class="profile">
    <div class="profile__cover">
        <?php if ($cover): ?>
            <img src="<?= e($cover) ?>" alt="" decoding="async">
        <?php endif; ?>
    </div>

    <div class="profile__head">
        <?php if (!empty($storyRing)): ?>
            <a class="<?= cx('profile__avatar', 'profile__avatar--story', ['is-seen' => !$storyRing['unseen'] && !$isOwn]) ?>"
                href="<?= e(url('stories.php', ['u' => $profile['username']])) ?>" aria-label="Ver la historia de <?= e($profile['display_name']) ?>">
                <?= avatar($profile, 'xl') ?>
            </a>
        <?php else: ?>
            <div class="profile__avatar"><?= avatar($profile, 'xl') ?></div>
        <?php endif; ?>
        <div class="profile__actions">
            <?php if ($isOwn): ?>
                <a class="btn btn--secondary" href="<?= e(url('edit-profile.php')) ?>"><?= icon('pencil') ?> Editar perfil</a>
            <?php elseif (!$isBlocked): ?>
                <?php View::partial('follow-button', ['user' => $profile]); ?>
                <?php if ($message['blocked'] === null): ?>
                    <a class="icon-btn icon-btn--outline" href="<?= e($message['url']) ?>" aria-label="Enviar mensaje" data-tooltip="Enviar mensaje"><?= icon('send') ?></a>
                <?php else: ?>
                    <button type="button" class="icon-btn icon-btn--outline" disabled aria-label="Enviar mensaje" data-tooltip="<?= e($message['blocked']) ?>"><?= icon('send') ?></button>
                <?php endif; ?>
            <?php endif; ?>
            <button type="button" class="icon-btn icon-btn--outline js-only" data-share-out="<?= e(profile_url($profile)) ?>"
                data-share-title="<?= e($profile['display_name'] . ' (@' . $profile['username'] . ') en TREVIX') ?>" aria-label="Compartir perfil" data-tooltip="Compartir">
                <?= icon('share-2') ?>
            </button>
            <button type="button" class="icon-btn icon-btn--outline" data-copy-url="<?= e(profile_url($profile)) ?>" aria-label="Copiar enlace del perfil" data-tooltip="Copiar enlace">
                <?= icon('link') ?>
            </button>
            <?php if ($canAct): ?>
                <div class="dropdown" data-dropdown>
                    <button type="button" class="icon-btn icon-btn--outline" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false" aria-label="Más opciones">
                        <?= icon('ellipsis') ?>
                    </button>
                    <div class="dropdown__menu" role="menu" hidden>
                        <?php if ($isBlocked): ?>
                            <form method="post" action="<?= e(url('api/blocks.php')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="unblock">
                                <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                                <button type="submit" class="dropdown__item" role="menuitem"><?= icon('user-check') ?> Desbloquear a @<?= e($profile['username']) ?></button>
                            </form>
                        <?php else: ?>
                            <form method="post" action="<?= e(url('api/blocks.php')) ?>"
                                data-confirm="¿Bloquear a @<?= e($profile['username']) ?>? Dejarán de seguirse mutuamente y ninguno podrá ver el perfil ni las publicaciones del otro."
                                data-confirm-label="Bloquear">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="block">
                                <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                                <button type="submit" class="dropdown__item dropdown__item--danger" role="menuitem"><?= icon('ban') ?> Bloquear a @<?= e($profile['username']) ?></button>
                            </form>
                        <?php endif; ?>
                        <a class="dropdown__item dropdown__item--danger" role="menuitem" href="<?= e(url('report.php', ['type' => 'user', 'id' => (int) $profile['id']])) ?>"
                            data-report="user" data-report-id="<?= (int) $profile['id'] ?>" data-report-label="la cuenta @<?= e($profile['username']) ?>"><?= icon('flag') ?> Reportar a @<?= e($profile['username']) ?></a>
                    </div>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <div class="profile__info">
        <h1 class="profile__name">
            <?= e($profile['display_name']) ?>
            <?= $profile['is_verified'] ? icon('badge-check', 'verified verified--lg', 'Cuenta verificada') : '' ?>
        </h1>
        <p class="profile__handle">
            @<?= e($profile['username']) ?>
            <?php if ($profile['is_private']): ?>
                <span class="chip chip--muted"><?= icon('lock') ?> Privada</span>
            <?php endif; ?>
            <?php if (!$isOwn && $relation['follows_you']): ?>
                <span class="chip chip--muted">Te sigue</span>
            <?php endif; ?>
        </p>
        <?php $creatorLabel = User::creatorLabel($profile); ?>
        <?php if ($creatorLabel !== null): ?>
            <p class="profile__creator">
                <span class="creator-badge"><?= icon(User::isMusicArtist($profile) ? 'mic-vocal' : 'sparkles') ?> <?= e($creatorLabel) ?></span>
            </p>
        <?php endif; ?>

        <?php if (!empty($profile['bio'])): ?>
            <p class="profile__bio"><?= format_post_body($profile['bio']) ?></p>
        <?php endif; ?>

        <ul class="profile__meta">
            <?php if (!empty($profile['country'])): ?>
                <li><?= icon('map-pin') ?> <?= e((require APP_PATH . '/Data/countries.php')[$profile['country']] ?? $profile['country']) ?></li>
            <?php endif; ?>
            <?php if (!empty($profile['website'])): ?>
                <li><?= icon('link') ?> <a href="<?= e($profile['website']) ?>" target="_blank" rel="noopener noreferrer nofollow"><?= e(preg_replace('~^https?://(www\.)?~', '', $profile['website'])) ?></a></li>
            <?php endif; ?>
            <li><?= icon('calendar') ?> Se unió en <?= e(spanish_months()[(int) date('n', $joined) - 1] . ' de ' . date('Y', $joined)) ?></li>
        </ul>

        <ul class="profile__stats">
            <li><a href="<?= e($tabUrl('posts')) ?>"><strong><?= e(compact_number((int) $profile['posts_count'])) ?></strong> publicaciones</a></li>
            <li><a href="<?= e($tabUrl('followers')) ?>"><strong data-followers-count="<?= (int) $profile['id'] ?>"><?= e(compact_number((int) $profile['followers_count'])) ?></strong> seguidores</a></li>
            <li><a href="<?= e($tabUrl('following')) ?>"><strong><?= e(compact_number((int) $profile['following_count'])) ?></strong> seguidos</a></li>
        </ul>
    </div>

    <nav class="tabs tabs--profile" aria-label="Contenido del perfil">
        <?php foreach ($tabs as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e($tabUrl($key)) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>

    <div class="profile__content" <?= !$isOwn && !$isBlocked && $profile['is_private'] ? 'data-reload-on-follow="' . (int) $profile['id'] . '"' : '' ?>>
        <?php if ($isBlocked): ?>
            <div class="locked">
                <span class="locked__icon"><?= icon('ban') ?></span>
                <h2>Bloqueaste a @<?= e($profile['username']) ?></h2>
                <p>No pueden ver el perfil ni las publicaciones del otro, ni seguirse. Puedes desbloquear la cuenta cuando quieras.</p>
                <form method="post" action="<?= e(url('api/blocks.php')) ?>">
                    <?= csrf_field() ?>
                    <input type="hidden" name="action" value="unblock">
                    <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                    <button type="submit" class="btn btn--secondary">Desbloquear</button>
                </form>
            </div>
        <?php elseif ($tab === 'music'): ?>
            <?php if ($songs === []): ?>
                <?php View::partial('empty-state', $isOwn
                    ? ['icon' => 'music', 'heading' => 'Aún no tienes canciones publicadas', 'text' => 'Cuando el equipo apruebe tus canciones, aparecerán aquí y en la biblioteca de música.', 'actionHref' => url('artist.php'), 'actionLabel' => 'Ir a Artista']
                    : ['icon' => 'music', 'heading' => 'Sin canciones todavía', 'text' => 'Cuando publique música en TREVIX, la escucharás aquí.']); ?>
            <?php else: ?>
                <div class="song-list song-list--profile">
                    <?php foreach ($songs as $song): ?>
                        <?php View::partial('song-row', ['song' => $song]); ?>
                    <?php endforeach; ?>
                </div>
                <?php if ($songsNext !== null): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($songsNext) ?>">Ver más canciones</a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif (!$canView): ?>
            <div class="locked">
                <span class="locked__icon"><?= icon('lock-keyhole') ?></span>
                <h2>Esta cuenta es privada</h2>
                <?php if ($relation['requested']): ?>
                    <p>Tu solicitud para seguir a @<?= e($profile['username']) ?> está pendiente. Cuando la apruebe, verás sus publicaciones, seguidores y seguidos.</p>
                <?php else: ?>
                    <p>Sigue a @<?= e($profile['username']) ?> para ver sus publicaciones, seguidores y seguidos. Tu solicitud deberá ser aprobada.</p>
                <?php endif; ?>
                <?php View::partial('follow-button', ['user' => $profile]); ?>
            </div>
        <?php elseif (in_array($tab, ['followers', 'following'], true)): ?>
            <?php if ($people === []): ?>
                <?php View::partial('empty-state', [
                    'icon' => 'users',
                    'heading' => $tab === 'followers' ? 'Sin seguidores todavía' : 'Aún no sigue a nadie',
                    'text' => 'Las conexiones aparecerán aquí.',
                ]); ?>
            <?php else: ?>
                <ul class="user-list user-list--padded">
                    <?php foreach ($people as $user): ?>
                        <li class="user-row">
                            <a class="user-row__link" href="<?= e(profile_url($user)) ?>">
                                <?= avatar($user, 'md') ?>
                                <span class="user-row__text">
                                    <span class="user-row__name"><?= e($user['display_name']) ?> <?= $user['is_verified'] ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?></span>
                                    <span class="user-row__meta">@<?= e($user['username']) ?><?= relation_of($user)['follows_you'] && (!$isOwn || $tab !== 'followers') ? ' · Te sigue' : '' ?></span>
                                </span>
                            </a>
                            <?php if (!$viewer || $user['username'] !== $viewer['username']): ?>
                                <div class="user-row__actions">
                                    <?php View::partial('follow-button', ['user' => $user, 'size' => 'sm', 'idle' => 'btn--light', 'compact' => true]); ?>
                                    <?php if ($isOwn && $tab === 'followers' && Auth::check()): ?>
                                        <form method="post" action="<?= e(url('api/follows.php')) ?>"
                                            data-confirm="¿Quitar a @<?= e($user['username']) ?> de tus seguidores? No se le avisará." data-confirm-label="Quitar">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="action" value="remove">
                                            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
                                            <button type="submit" class="icon-btn icon-btn--sm" aria-label="Quitar a @<?= e($user['username']) ?> de tus seguidores" data-tooltip="Quitar seguidor"><?= icon('user-minus') ?></button>
                                        </form>
                                    <?php endif; ?>
                                </div>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <?php if (!empty($peopleNext)): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($peopleNext) ?>">Ver más</a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif ($tab === 'media'): ?>
            <?php
            $tiles = [];
            foreach ($list['posts'] as $post) {
                foreach ($post['media'] as $item) {
                    $tiles[] = $item + ['post_id' => (int) $post['id']];
                }
            }
            $imageIndex = 0;
            ?>
            <?php if ($tiles === []): ?>
                <?php View::partial('empty-state', ['icon' => 'image', 'heading' => 'Sin fotos ni videos', 'text' => 'Las imágenes y videos publicados aparecerán aquí.']); ?>
            <?php else: ?>
                <div class="media-grid media-grid--profile" data-lightbox-group>
                    <?php foreach ($tiles as $item): ?>
                        <?php if ($item['type'] === 'video'): ?>
                            <a class="media-tile media-tile--video" href="<?= e(url('post.php', ['id' => $item['post_id']])) ?>" aria-label="Ver video">
                                <video src="<?= e(url($item['src'])) ?>#t=0.1" preload="metadata" muted playsinline></video>
                                <span class="media-tile__badge"><?= icon('play') ?></span>
                            </a>
                        <?php else: ?>
                            <button type="button" class="media-tile" data-lightbox-index="<?= $imageIndex ?>" aria-label="Ver imagen <?= $imageIndex + 1 ?>">
                                <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['alt'] ?? '') ?>" loading="lazy" decoding="async">
                            </button>
                            <?php $imageIndex++; ?>
                        <?php endif; ?>
                    <?php endforeach; ?>
                </div>
                <?php if (!empty($list['nextUrl'])): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($list['nextUrl']) ?>">Ver más</a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif ($list['posts'] === []): ?>
            <?php
            $empty = match (true) {
                $tab === 'saved' => ['bookmark', 'Aún no guardaste nada', 'Toca el marcador de una publicación para guardarla aquí. Solo tú ves esta lista.'],
                $isOwn => [$tab === 'threads' ? 'messages-square' : 'file-text', 'Todavía no has publicado', 'Comparte tu primera foto, video o idea con tus seguidores.'],
                default => [$tab === 'threads' ? 'messages-square' : 'file-text', 'Sin publicaciones todavía', 'Cuando publique algo, lo verás aquí.'],
            };
            ?>
            <?php View::partial('empty-state', ['icon' => $empty[0], 'heading' => $empty[1], 'text' => $empty[2]]); ?>
        <?php else: ?>
            <div class="feed" <?= $isOwn && $tab === 'posts' ? 'data-feed-live="post thread"' : ($isOwn && $tab === 'threads' ? 'data-feed-live="thread"' : '') ?>>
                <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => null]); ?>
            </div>
        <?php endif; ?>
    </div>
</section>
