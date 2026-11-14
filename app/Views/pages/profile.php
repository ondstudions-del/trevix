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
 * @var array|null  $collaborator CollaboratorService::profileOffer()
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
                href="<?= e(url('stories.php', ['u' => $profile['username']])) ?>" aria-label="<?= e(t('Ver la historia de {name}', ['name' => $profile['display_name']])) ?>">
                <?= avatar($profile, 'xl') ?>
            </a>
        <?php else: ?>
            <div class="profile__avatar"><?= avatar($profile, 'xl') ?></div>
        <?php endif; ?>
        <div class="profile__actions">
            <?php if ($isOwn): ?>
                <a class="btn btn--secondary" href="<?= e(url('edit-profile.php')) ?>"><?= icon('pencil') ?> <?= e(t('Editar perfil')) ?></a>
            <?php elseif (!$isBlocked): ?>
                <?php View::partial('follow-button', ['user' => $profile]); ?>
                <?php if ($message['blocked'] === null): ?>
                    <a class="icon-btn icon-btn--outline" href="<?= e($message['url']) ?>" aria-label="<?= e(t('Enviar mensaje')) ?>" data-tooltip="<?= e(t('Enviar mensaje')) ?>"><?= icon('send') ?></a>
                <?php else: ?>
                    <button type="button" class="icon-btn icon-btn--outline" disabled aria-label="<?= e(t('Enviar mensaje')) ?>" data-tooltip="<?= e(t($message['blocked'])) ?>"><?= icon('send') ?></button>
                <?php endif; ?>
                <?php if ($canAct && $canView): ?>
                    <form method="post" action="<?= e(url('api/alerts.php')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                        <input type="hidden" name="action" value="<?= !empty($alertsOn) ? 'off' : 'on' ?>">
                        <?php $alertLabel = !empty($alertsOn) ? t('Desactivar avisos de sus publicaciones') : t('Avisarme cuando publique, comparta una nota o suba una historia'); ?>
                        <button type="submit" class="<?= cx('icon-btn', 'icon-btn--outline', ['is-active' => !empty($alertsOn)]) ?>"
                            aria-pressed="<?= !empty($alertsOn) ? 'true' : 'false' ?>" aria-label="<?= e($alertLabel) ?>" data-tooltip="<?= e($alertLabel) ?>">
                            <?= icon(!empty($alertsOn) ? 'bell-ring' : 'bell') ?>
                        </button>
                    </form>
                <?php endif; ?>
                <?php if ($canAct): ?>
                    <a class="icon-btn icon-btn--outline" href="<?= e(url('gifts.php', ['to' => $profile['username']])) ?>"
                        aria-label="<?= e(t('Enviar un regalo')) ?>" data-tooltip="<?= e(t('Enviar un regalo')) ?>"><?= icon('gift') ?></a>
                <?php endif; ?>
            <?php endif; ?>
            <button type="button" class="icon-btn icon-btn--outline js-only" data-share-out="<?= e(profile_url($profile)) ?>"
                data-share-title="<?= e(t('{name} (@{username}) en TREVIX', ['name' => $profile['display_name'], 'username' => $profile['username']])) ?>" aria-label="<?= e(t('Compartir perfil')) ?>" data-tooltip="<?= e(t('Compartir')) ?>">
                <?= icon('share-2') ?>
            </button>
            <button type="button" class="icon-btn icon-btn--outline" data-copy-url="<?= e(profile_url($profile)) ?>" aria-label="<?= e(t('Copiar enlace del perfil')) ?>" data-tooltip="<?= e(t('Copiar enlace')) ?>">
                <?= icon('link') ?>
            </button>
            <?php if ($canAct): ?>
                <div class="dropdown" data-dropdown>
                    <button type="button" class="icon-btn icon-btn--outline" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false" aria-label="<?= e(t('Más opciones')) ?>">
                        <?= icon('ellipsis') ?>
                    </button>
                    <div class="dropdown__menu" role="menu" hidden>
                        <?php if ($isBlocked): ?>
                            <form method="post" action="<?= e(url('api/blocks.php')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="unblock">
                                <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                                <button type="submit" class="dropdown__item" role="menuitem"><?= icon('user-check') ?> <?= e(t('Desbloquear a @{username}', ['username' => $profile['username']])) ?></button>
                            </form>
                        <?php else: ?>
                            <form method="post" action="<?= e(url('api/blocks.php')) ?>"
                                data-confirm="<?= e(t('¿Bloquear a @{username}? Dejarán de seguirse mutuamente y ninguno podrá ver el perfil ni las publicaciones del otro.', ['username' => $profile['username']])) ?>"
                                data-confirm-label="<?= e(t('Bloquear')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="block">
                                <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                                <button type="submit" class="dropdown__item dropdown__item--danger" role="menuitem"><?= icon('ban') ?> <?= e(t('Bloquear a @{username}', ['username' => $profile['username']])) ?></button>
                            </form>
                        <?php endif; ?>
                        <a class="dropdown__item dropdown__item--danger" role="menuitem" href="<?= e(url('report.php', ['type' => 'user', 'id' => (int) $profile['id']])) ?>"
                            data-report="user" data-report-id="<?= (int) $profile['id'] ?>" data-report-label="<?= e(t('la cuenta @{username}', ['username' => $profile['username']])) ?>"><?= icon('flag') ?> <?= e(t('Reportar a @{username}', ['username' => $profile['username']])) ?></a>
                    </div>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <div class="profile__info">
        <h1 class="profile__name">
            <?= e($profile['display_name']) ?>
            <?= $profile['is_verified'] ? icon('badge-check', 'verified verified--lg', t('Cuenta verificada')) : '' ?>
        </h1>
        <p class="profile__handle">
            @<?= e($profile['username']) ?>
            <?php if ($profile['is_private']): ?>
                <span class="chip chip--muted"><?= icon('lock') ?> <?= e(t('Privada')) ?></span>
            <?php endif; ?>
            <?php if (!$isOwn && $relation['follows_you']): ?>
                <span class="chip chip--muted"><?= e(t('Te sigue')) ?></span>
            <?php endif; ?>
        </p>
        <?php $creatorLabel = User::creatorLabel($profile); ?>
        <?php if ($creatorLabel !== null): ?>
            <p class="profile__creator">
                <span class="creator-badge"><?= icon(User::isMusicArtist($profile) ? 'mic-vocal' : 'sparkles') ?> <?= e(t($creatorLabel)) ?></span>
            </p>
        <?php endif; ?>

        <?php if (!empty($profile['bio'])): ?>
            <p class="profile__bio"><?= format_post_body($profile['bio']) ?></p>
        <?php endif; ?>

        <ul class="profile__meta">
            <?php if (!empty($profile['country'])): ?>
                <li><?= icon('map-pin') ?> <?= e(trim(country_flag((string) $profile['country']) . ' ' . (\Trevix\Services\ProfileService::countries()[$profile['country']] ?? $profile['country']))) ?></li>
            <?php endif; ?>
            <?php if (!empty($profile['website'])): ?>
                <li><?= icon('link') ?> <a href="<?= e($profile['website']) ?>" target="_blank" rel="noopener noreferrer nofollow"><?= e(preg_replace('~^https?://(www\.)?~', '', $profile['website'])) ?></a></li>
            <?php endif; ?>
            <li><?= icon('calendar') ?> <?= e(t('Se unió en {month} de {year}', ['month' => spanish_months()[(int) date('n', $joined) - 1], 'year' => date('Y', $joined)])) ?></li>
        </ul>

        <ul class="profile__stats">
            <li><a href="<?= e($tabUrl('posts')) ?>"><?= tn((int) $profile['posts_count'], '{n} publicación', '{n} publicaciones', ['n' => '<strong>' . e(compact_number((int) $profile['posts_count'])) . '</strong>']) ?></a></li>
            <li><a href="<?= e($tabUrl('followers')) ?>"><?= tn((int) $profile['followers_count'], '{n} seguidor', '{n} seguidores', ['n' => '<strong data-followers-count="' . (int) $profile['id'] . '">' . e(compact_number((int) $profile['followers_count'])) . '</strong>']) ?></a></li>
            <li><a href="<?= e($tabUrl('following')) ?>"><?= tn((int) $profile['following_count'], '{n} seguido', '{n} seguidos', ['n' => '<strong>' . e(compact_number((int) $profile['following_count'])) . '</strong>']) ?></a></li>
        </ul>
    </div>

    <?php if (!empty($collaborator)): ?>
        <aside class="profile-collab" aria-label="<?= e(t('Contenido para suscriptores')) ?>">
            <p class="profile-collab__title"><?= icon('crown') ?> <?= e(t('Colaborador')) ?></p>
            <?php if ($collaborator['description'] !== null && $collaborator['description'] !== ''): ?>
                <p class="profile-collab__text">«<?= e($collaborator['description']) ?>»</p>
            <?php endif; ?>
            <p class="profile-collab__text">
                <?= e(plural((int) $collaborator['exclusive_posts'], 'publicación exclusiva', 'publicaciones exclusivas')) ?>
                <?php if ($collaborator['price'] !== null): ?>
                    · <?= e(t('{price} por {days} días', ['price' => $collaborator['price']['formatted'], 'days' => (int) $collaborator['days']])) ?>
                <?php endif; ?>
            </p>
            <?php if ($collaborator['is_owner']): ?>
                <a class="btn btn--secondary btn--sm" href="<?= e(url('wallet.php', ['tab' => 'collaborator'])) ?>"><?= icon('crown') ?> <?= e(t('Gestionar mi plan')) ?></a>
            <?php else: ?>
                <?php if ($collaborator['access_until'] !== null): ?>
                    <p class="profile-collab__text"><?= icon('circle-check') ?> <?= e(t('Tienes acceso hasta el {date}.', ['date' => full_date((string) $collaborator['access_until'], false)])) ?></p>
                <?php endif; ?>
                <?php if ($collaborator['accepting'] && $collaborator['price'] !== null): ?>
                    <form method="post" action="<?= e(url('wallet.php')) ?>" data-confirm-label="<?= e(t('Pagar')) ?>"
                        data-confirm="<?= e(t('¿Pagar {price} de tu monedero para ver el contenido exclusivo de {name} durante {days} días?', [
                            'price' => $collaborator['price']['formatted'], 'name' => $profile['display_name'], 'days' => (int) $collaborator['days'],
                        ])) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="subscribe">
                        <input type="hidden" name="collaborator_id" value="<?= (int) $profile['id'] ?>">
                        <button type="submit" class="btn btn--primary btn--sm"><?= icon('crown') ?> <?= e($collaborator['access_until'] !== null ? t('Extender suscripción') : t('Suscribirme')) ?></button>
                    </form>
                    <p class="profile-collab__text">
                        <?= e(t('Sin reembolsos, salvo cobros duplicados o errores técnicos.')) ?>
                        <a href="<?= e(url('legal.php', ['doc' => 'reembolsos'])) ?>" target="_blank" rel="noopener"><?= e(t('Política de reembolsos')) ?></a>
                    </p>
                <?php endif; ?>
            <?php endif; ?>
        </aside>
    <?php endif; ?>

    <nav class="tabs tabs--profile" aria-label="<?= e(t('Contenido del perfil')) ?>">
        <?php foreach ($tabs as $key => $label): ?>
            <?php $tabIcon = ['posts' => 'layout-grid', 'threads' => 'messages-square', 'lists' => 'list', 'media' => 'image', 'music' => 'music', 'saved' => 'bookmark'][$key] ?? null; ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key, 'tabs__item--icon' => $tabIcon !== null]) ?>" href="<?= e($tabUrl($key)) ?>"
                <?= $tabIcon !== null ? 'aria-label="' . e(t($label)) . '" data-tooltip="' . e(t($label)) . '"' : '' ?>
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= $tabIcon !== null ? icon($tabIcon) : e(t($label)) ?></a>
        <?php endforeach; ?>
    </nav>

    <?php if ($tab === 'saved' && $isOwn): ?>
        <?php
        $savedUrl = static fn (string $cat, string $kind = 'all') => url('profile.php', ['u' => $profile['username'], 'tab' => 'saved', 'cat' => $cat === 'saved' ? null : $cat, 'kind' => $kind === 'all' ? null : $kind]);
        $kinds = ['all' => 'Todo', 'posts' => 'Publicaciones', 'reels' => 'Reels'] + ($savedCat === 'private' ? ['stories' => 'Historias'] : []);
        ?>
        <nav class="saved-nav" aria-label="<?= e(t('Categorías de Guardado')) ?>">
            <div class="saved-nav__cats">
                <?php foreach (['saved' => ['bookmark', 'Guardados'], 'private' => ['lock', 'Solo yo'], 'liked' => ['heart', 'Me gusta']] as $cat => [$catIcon, $catLabel]): ?>
                    <a class="<?= cx('chip', ['is-active' => $savedCat === $cat]) ?>" href="<?= e($savedUrl($cat)) ?>" <?= $savedCat === $cat ? 'aria-current="page"' : '' ?>>
                        <?= icon($catIcon) ?> <?= e(t($catLabel)) ?>
                    </a>
                <?php endforeach; ?>
            </div>
            <div class="saved-nav__kinds">
                <?php foreach ($kinds as $kind => $kindLabel): ?>
                    <a class="<?= cx('saved-nav__kind', ['is-active' => $savedKind === $kind]) ?>" href="<?= e($savedUrl($savedCat, $kind)) ?>" <?= $savedKind === $kind ? 'aria-current="page"' : '' ?>><?= e(t($kindLabel)) ?></a>
                <?php endforeach; ?>
            </div>
        </nav>
    <?php endif; ?>

    <div class="profile__content" <?= !$isOwn && !$isBlocked && $profile['is_private'] ? 'data-reload-on-follow="' . (int) $profile['id'] . '"' : '' ?>>
        <?php if ($isBlocked): ?>
            <div class="locked">
                <span class="locked__icon"><?= icon('ban') ?></span>
                <h2><?= e(t('Bloqueaste a @{username}', ['username' => $profile['username']])) ?></h2>
                <p><?= e(t('No pueden ver el perfil ni las publicaciones del otro, ni seguirse. Puedes desbloquear la cuenta cuando quieras.')) ?></p>
                <form method="post" action="<?= e(url('api/blocks.php')) ?>">
                    <?= csrf_field() ?>
                    <input type="hidden" name="action" value="unblock">
                    <input type="hidden" name="user_id" value="<?= (int) $profile['id'] ?>">
                    <button type="submit" class="btn btn--secondary"><?= e(t('Desbloquear')) ?></button>
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
                        <a class="btn btn--secondary" href="<?= e($songsNext) ?>"><?= e(t('Ver más canciones')) ?></a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif (!$canView): ?>
            <div class="locked">
                <span class="locked__icon"><?= icon('lock-keyhole') ?></span>
                <h2><?= e(t('Esta cuenta es privada')) ?></h2>
                <?php if ($relation['requested']): ?>
                    <p><?= e(t('Tu solicitud para seguir a @{username} está pendiente. Cuando la apruebe, verás sus publicaciones, seguidores y seguidos.', ['username' => $profile['username']])) ?></p>
                <?php else: ?>
                    <p><?= e(t('Sigue a @{username} para ver sus publicaciones, seguidores y seguidos. Tu solicitud deberá ser aprobada.', ['username' => $profile['username']])) ?></p>
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
                                    <span class="user-row__name"><?= e($user['display_name']) ?> <?= $user['is_verified'] ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?></span>
                                    <span class="user-row__meta">@<?= e($user['username']) ?><?= relation_of($user)['follows_you'] && (!$isOwn || $tab !== 'followers') ? ' · ' . e(t('Te sigue')) : '' ?></span>
                                </span>
                            </a>
                            <?php if (!$viewer || $user['username'] !== $viewer['username']): ?>
                                <div class="user-row__actions">
                                    <?php View::partial('follow-button', ['user' => $user, 'size' => 'sm', 'idle' => 'btn--light', 'compact' => true]); ?>
                                    <?php if ($isOwn && $tab === 'followers' && Auth::check()): ?>
                                        <form method="post" action="<?= e(url('api/follows.php')) ?>"
                                            data-confirm="<?= e(t('¿Quitar a @{username} de tus seguidores? No se le avisará.', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Quitar')) ?>">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="action" value="remove">
                                            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
                                            <button type="submit" class="icon-btn icon-btn--sm" aria-label="<?= e(t('Quitar a @{username} de tus seguidores', ['username' => $user['username']])) ?>" data-tooltip="<?= e(t('Quitar seguidor')) ?>"><?= icon('user-minus') ?></button>
                                        </form>
                                    <?php endif; ?>
                                </div>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <?php if (!empty($peopleNext)): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($peopleNext) ?>"><?= e(t('Ver más')) ?></a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif ($tab === 'lists'): ?>
            <?php if ($isOwn): ?>
                <details class="card playlist-new" <?= $playlists === [] ? 'open' : '' ?>>
                    <summary class="playlist-new__summary"><?= icon('plus') ?> <?= e(t('Nueva lista de reproducción')) ?></summary>
                    <form class="playlist-new__form" method="post" action="<?= e(url('api/playlists.php')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="create">
                        <label class="field">
                            <span class="field__label"><?= e(t('Nombre')) ?></span>
                            <input class="input" type="text" name="title" required maxlength="80">
                        </label>
                        <label class="field">
                            <span class="field__label"><?= e(t('Descripción (opcional)')) ?></span>
                            <textarea class="input" name="description" rows="2" maxlength="300"></textarea>
                        </label>
                        <p class="field__hint"><?= e(t('Agrega tus reels desde el menú «⋯» de cada video. Se reproducen en el orden en que los agregues.')) ?></p>
                        <button type="submit" class="btn btn--primary"><?= e(t('Crear lista')) ?></button>
                    </form>
                </details>
            <?php endif; ?>
            <?php if ($playlists === []): ?>
                <?php View::partial('empty-state', $isOwn
                    ? ['icon' => 'list', 'heading' => 'Aún no tienes listas', 'text' => 'Agrupa tus reels en listas: quien las abra los verá en el orden en que los publicaste en la lista.']
                    : ['icon' => 'list', 'heading' => 'Sin listas todavía', 'text' => 'Cuando cree listas de reproducción, las verás aquí.']); ?>
            <?php else: ?>
                <div class="playlist-grid">
                    <?php foreach ($playlists as $playlist): ?>
                        <?php View::partial('playlist-card', ['playlist' => $playlist]); ?>
                    <?php endforeach; ?>
                </div>
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
                            <a class="media-tile media-tile--video" href="<?= e(url('post.php', ['id' => $item['post_id']])) ?>" aria-label="<?= e(t('Ver video')) ?>">
                                <?php if (!empty($item['poster'])): ?>
                                    <img src="<?= e(url($item['poster'])) ?>" alt="" loading="lazy" decoding="async">
                                <?php else: ?>
                                    <video src="<?= e(url($item['src'])) ?>#t=0.1" preload="metadata" muted playsinline></video>
                                <?php endif; ?>
                                <span class="media-tile__badge"><?= icon('play') ?></span>
                            </a>
                        <?php else: ?>
                            <button type="button" class="media-tile" data-lightbox-index="<?= $imageIndex ?>" aria-label="<?= e(t('Ver imagen {n}', ['n' => $imageIndex + 1])) ?>">
                                <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['alt'] ?? '') ?>" loading="lazy" decoding="async">
                            </button>
                            <?php $imageIndex++; ?>
                        <?php endif; ?>
                    <?php endforeach; ?>
                </div>
                <?php if (!empty($list['nextUrl'])): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($list['nextUrl']) ?>"><?= e(t('Ver más')) ?></a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif ($tab === 'saved' && $savedKind === 'stories'): ?>
            <?php if ($privateStories === []): ?>
                <?php View::partial('empty-state', ['icon' => 'lock', 'heading' => 'No tienes historias en Solo yo', 'text' => 'Desde la app, al publicar una historia o en el menú de una historia tuya, elige «Solo yo»: nadie más la verá y no se borrará a las 24 horas.']); ?>
            <?php else: ?>
                <?php $imageIndex = 0; ?>
                <div class="media-grid media-grid--profile media-grid--stories" data-lightbox-group>
                    <?php foreach ($privateStories as $story): ?>
                        <?php if ($story['type'] === 'video'): ?>
                            <a class="media-tile media-tile--video" href="<?= e(url($story['src'])) ?>" target="_blank" rel="noopener" aria-label="<?= e(t('Ver video')) ?>">
                                <video src="<?= e(url($story['src'])) ?>#t=0.1" preload="metadata" muted playsinline></video>
                                <span class="media-tile__badge"><?= icon('play') ?></span>
                            </a>
                        <?php elseif ($story['type'] === 'image'): ?>
                            <button type="button" class="media-tile" data-lightbox-index="<?= $imageIndex ?>" aria-label="<?= e(t('Ver imagen {n}', ['n' => $imageIndex + 1])) ?>">
                                <img src="<?= e(url($story['src'])) ?>" alt="" loading="lazy" decoding="async">
                            </button>
                            <?php $imageIndex++; ?>
                        <?php else: ?>
                            <div class="media-tile media-tile--text story-bg--<?= e($story['background'] ?: 'violet') ?>">
                                <span><?= e(mb_strimwidth((string) $story['body'], 0, 120, '…')) ?></span>
                            </div>
                        <?php endif; ?>
                    <?php endforeach; ?>
                </div>
                <?php if ($privateStoriesNext !== null): ?>
                    <div class="load-more">
                        <a class="btn btn--secondary" href="<?= e($privateStoriesNext) ?>"><?= e(t('Ver más')) ?></a>
                    </div>
                <?php endif; ?>
            <?php endif; ?>
        <?php elseif ($list['posts'] === []): ?>
            <?php
            $empty = match (true) {
                $tab === 'saved' && $savedCat === 'private' => ['lock', 'Nada en Solo yo', 'Las publicaciones, reels e historias que publiques con la visibilidad «Solo yo» aparecerán aquí. Nadie más las ve.'],
                $tab === 'saved' && $savedCat === 'liked' => ['heart', 'Aún no te gusta nada', 'Las publicaciones y reels a los que les des me gusta aparecerán aquí. Solo tú ves esta lista.'],
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
