<?php

use Trevix\Core\Config;
use Trevix\Core\View;
use Trevix\Models\Community;

/**
 * @var array       $community
 * @var array       $access   member | owner | manager | banned | pending | canView | canPost
 * @var string      $tab
 * @var array       $tabs
 * @var array|null  $list     publicaciones (pestañas posts y popular)
 * @var array|null  $members  personas (pestañas members y requests)
 * @var string      $status   active | pending | banned
 * @var string|null $nextUrl
 * @var int         $pendingCount
 * @var array       $categories
 * @var array       $errors
 * @var array       $old
 * @var array|null  $viewer
 * @var bool        $isPreview
 */
$private = $community['visibility'] === 'private';
$viewerId = (int) ($viewer['id'] ?? 0);
$limits = Config::get('app.limits');
$csrfAction = static function (string $action, int $userId, string $label, string $class, string $icon, string $confirm = '') use ($community): string {
    return '<form method="post" action="' . e(url('api/communities.php')) . '"'
        . ($confirm !== '' ? ' data-confirm="' . e($confirm) . '" data-confirm-label="' . e($label) . '"' : '') . '>'
        . csrf_field()
        . '<input type="hidden" name="action" value="' . e($action) . '">'
        . '<input type="hidden" name="community_id" value="' . (int) $community['id'] . '">'
        . '<input type="hidden" name="user_id" value="' . $userId . '">'
        . '<button type="submit" class="' . e($class) . '"' . (str_contains($class, 'dropdown__item') ? ' role="menuitem"' : '') . '>'
        . icon($icon) . ' ' . e($label) . '</button></form>';
};
?>
<section class="community-hero" aria-labelledby="community-name">
    <div class="community-hero__cover">
        <img src="<?= e(community_cover($community)) ?>" alt="">
    </div>
    <div class="community-hero__body">
        <div class="community-hero__top">
            <?= community_icon($community, 'xl') ?>
            <div class="community-hero__actions">
                <?php View::partial('community-join', ['community' => $community]); ?>
                <?php if ($viewerId > 0 && !$isPreview && !$access['owner']): ?>
                    <a class="icon-btn icon-btn--outline" href="<?= e(url('report.php', ['type' => 'community', 'id' => (int) $community['id']])) ?>"
                        data-report="community" data-report-id="<?= (int) $community['id'] ?>" data-report-label="la comunidad «<?= e($community['name']) ?>»"
                        aria-label="Reportar comunidad" data-tooltip="Reportar comunidad"><?= icon('flag') ?></a>
                <?php endif; ?>
            </div>
        </div>
        <h1 class="community-hero__name" id="community-name"><?= e($community['name']) ?></h1>
        <p class="community-hero__meta">
            <span><?= $private ? icon('lock') . ' Comunidad privada' : icon('globe') . ' Comunidad pública' ?></span>
            <?php if ($community['category'] !== ''): ?>
                <span><?= icon('layout-grid') ?> <?= e($community['category']) ?></span>
            <?php endif; ?>
            <span><?= icon('users') ?> <strong data-community-members="<?= (int) $community['id'] ?>"><?= e(compact_number($community['members_count'])) ?></strong>
                <span data-community-members-label="<?= (int) $community['id'] ?>"><?= plural((int) $community['members_count'], 'miembro', 'miembros') ?></span></span>
            <span><?= icon('file-text') ?> <strong><?= e(compact_number($community['posts_count'])) ?></strong> <?= plural((int) $community['posts_count'], 'publicación', 'publicaciones') ?></span>
        </p>
        <?php if ($community['description'] !== ''): ?>
            <p class="community-hero__desc"><?= nl2br(e($community['description'])) ?></p>
        <?php endif; ?>
        <?php if (!empty($community['owner'])): ?>
            <p class="community-hero__owner">
                <?= icon('crown') ?> Administrada por <a href="<?= e(profile_url($community['owner'])) ?>"><?= e($community['owner']['display_name']) ?></a>
                · creada el <?= e(date('j/m/Y', strtotime($community['created_at']) ?: time())) ?>
            </p>
        <?php endif; ?>
    </div>
    <nav class="tabs community-hero__tabs" aria-label="Secciones de la comunidad">
        <?php foreach ($tabs as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(community_url($community, ['tab' => $key === 'posts' ? null : $key])) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>>
                <?= e($label) ?>
                <?php if ($key === 'requests' && $pendingCount > 0): ?>
                    <span class="tabs__badge"><?= $pendingCount ?></span>
                <?php endif; ?>
            </a>
        <?php endforeach; ?>
    </nav>
</section>

<?php if (in_array($tab, ['posts', 'popular', 'members'], true) && !$access['canView']): ?>
    <?php View::partial('empty-state', [
        'icon'    => 'lock',
        'heading' => 'Esta comunidad es privada',
        'text'    => $access['pending']
            ? 'Tu solicitud está pendiente. Cuando la acepten podrás ver y crear publicaciones.'
            : ($access['banned'] ? 'No puedes participar en esta comunidad.' : 'Solicita acceso para ver sus publicaciones y conocer a sus miembros.'),
    ]); ?>

<?php elseif ($tab === 'posts' || $tab === 'popular'): ?>
    <?php if ($access['canPost']): ?>
        <?php View::partial('composer-inline', ['viewer' => $viewer, 'community' => $community]); ?>
    <?php elseif ($access['banned']): ?>
        <p class="community-note"><?= icon('ban') ?> No puedes publicar en esta comunidad.</p>
    <?php elseif (!$isPreview && !$access['pending']): ?>
        <p class="community-note"><?= icon('info') ?> Únete a la comunidad para publicar en ella.</p>
    <?php endif; ?>
    <section class="feed" aria-label="Publicaciones de <?= e($community['name']) ?>"
        <?= $tab === 'posts' ? 'data-feed-live="post thread" data-feed-community="' . (int) $community['id'] . '"' : '' ?>>
        <?php if ($list['posts'] === []): ?>
            <?php View::partial('empty-state', [
                'icon'    => 'file-text',
                'heading' => $tab === 'popular' ? 'Aún no hay publicaciones populares' : 'Todavía no hay publicaciones',
                'text'    => $access['canPost'] ? 'Comparte la primera publicación de la comunidad.' : 'Cuando sus miembros publiquen, lo verás aquí.',
            ]); ?>
        <?php else: ?>
            <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => 'Ya viste todas las publicaciones de esta comunidad.']); ?>
        <?php endif; ?>
    </section>

<?php elseif ($tab === 'members' || $tab === 'requests'): ?>
    <?php if ($tab === 'members' && $access['manager']): ?>
        <nav class="chip-tabs" aria-label="Filtrar miembros">
            <a class="<?= cx('chip-tabs__item', ['is-active' => $status === 'active']) ?>" href="<?= e(community_url($community, ['tab' => 'members'])) ?>">Activos</a>
            <a class="<?= cx('chip-tabs__item', ['is-active' => $status === 'banned']) ?>" href="<?= e(community_url($community, ['tab' => 'members', 'status' => 'banned'])) ?>">Vetados</a>
        </nav>
    <?php endif; ?>

    <?php if ($members === []): ?>
        <?php View::partial('empty-state', match ($status) {
            'pending' => ['icon' => 'inbox', 'heading' => 'No hay solicitudes pendientes', 'text' => 'Cuando alguien pida unirse, aparecerá aquí para que lo apruebes.'],
            'banned'  => ['icon' => 'ban', 'heading' => 'No hay personas vetadas', 'text' => 'Las personas que vetes no podrán volver a unirse mientras dure el veto.'],
            default   => ['icon' => 'users', 'heading' => 'Sin miembros', 'text' => 'Todavía no hay miembros activos.'],
        }); ?>
    <?php else: ?>
        <ul class="member-list">
            <?php foreach ($members as $member): ?>
                <?php
                $memberId = (int) $member['id'];
                $isSelf = $memberId === $viewerId;
                $canBan = $access['manager'] && !$isSelf && $member['role'] !== 'owner' && ($access['owner'] || $member['role'] === 'member');
                $canRole = $access['owner'] && !$isSelf && $member['role'] !== 'owner';
                ?>
                <li class="member-row">
                    <a class="member-row__user" href="<?= e(profile_url($member)) ?>">
                        <?= avatar($member, 'md') ?>
                        <span class="member-row__text">
                            <span class="member-row__name">
                                <?= e($member['display_name']) ?>
                                <?= !empty($member['is_verified']) ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?>
                            </span>
                            <span class="member-row__meta">@<?= e($member['username']) ?> ·
                                <?= $status === 'pending' ? 'lo pidió' : ($status === 'banned' ? 'vetado' : 'se unió') ?> <?= time_tag($member['joined_at']) ?></span>
                        </span>
                    </a>
                    <?php if ($status === 'active' && $member['role'] !== 'member'): ?>
                        <span class="<?= $member['role'] === 'owner' ? 'chip chip--brand' : 'chip chip--muted' ?>">
                            <?= icon($member['role'] === 'owner' ? 'crown' : 'shield') ?> <?= e(Community::ROLES[$member['role']]) ?>
                        </span>
                    <?php endif; ?>

                    <?php if ($status === 'pending'): ?>
                        <div class="member-row__actions">
                            <?= $csrfAction('approve', $memberId, 'Aceptar', 'btn btn--primary btn--sm', 'check') ?>
                            <?= $csrfAction('reject', $memberId, 'Rechazar', 'btn btn--secondary btn--sm', 'x') ?>
                        </div>
                    <?php elseif ($status === 'banned'): ?>
                        <div class="member-row__actions">
                            <?= $csrfAction('unban', $memberId, 'Levantar veto', 'btn btn--secondary btn--sm', 'user-check', '¿Levantar el veto a @' . $member['username'] . '? Podrá volver a unirse.') ?>
                        </div>
                    <?php elseif ($canBan || $canRole): ?>
                        <div class="dropdown" data-dropdown>
                            <button type="button" class="icon-btn icon-btn--sm" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false"
                                aria-label="Opciones para @<?= e($member['username']) ?>"><?= icon('ellipsis') ?></button>
                            <div class="dropdown__menu" role="menu" hidden>
                                <?php if ($canRole): ?>
                                    <?= $member['role'] === 'moderator'
                                        ? $csrfAction('demote', $memberId, 'Quitar moderación', 'dropdown__item', 'user-minus')
                                        : $csrfAction('promote', $memberId, 'Nombrar moderador', 'dropdown__item', 'shield-check') ?>
                                <?php endif; ?>
                                <?php if ($canBan): ?>
                                    <?= $csrfAction('ban', $memberId, 'Vetar de la comunidad', 'dropdown__item dropdown__item--danger', 'ban',
                                        '¿Vetar a @' . $member['username'] . '? Saldrá de la comunidad y no podrá volver a unirse.') ?>
                                <?php endif; ?>
                            </div>
                        </div>
                    <?php endif; ?>
                </li>
            <?php endforeach; ?>
        </ul>
        <?php if ($nextUrl !== null): ?>
            <div class="community-more"><a class="btn btn--secondary" href="<?= e($nextUrl) ?>">Ver más</a></div>
        <?php endif; ?>
    <?php endif; ?>

<?php elseif ($tab === 'settings'): ?>
    <?php
    $value = static fn (string $key): string => (string) ($old[$key] ?? $community[$key] ?? '');
    $imageMimes = implode(',', Config::get('app.uploads.image.mimes'));
    $maxImageBytes = (int) Config::get('app.uploads.profile.max_bytes');
    ?>
    <?php if (isset($errors['avatar']) || isset($errors['cover'])): ?>
        <div class="alert alert--error community-alert" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e($errors['avatar'] ?? $errors['cover']) ?></p>
        </div>
    <?php endif; ?>

    <form class="form edit-profile community-settings" method="post" action="<?= e(url('api/communities.php')) ?>" enctype="multipart/form-data" novalidate data-validate>
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="update">
        <input type="hidden" name="community_id" value="<?= (int) $community['id'] ?>">

        <div class="edit-profile__media">
            <div class="edit-profile__cover">
                <img src="<?= e(community_cover($community)) ?>" alt="" data-preview="cover">
                <label class="btn btn--glass btn--sm edit-profile__upload">
                    <?= icon('camera') ?> Cambiar portada
                    <input class="sr-only" type="file" name="cover" accept="<?= e($imageMimes) ?>" data-image-preview="cover" data-max-bytes="<?= $maxImageBytes ?>">
                </label>
            </div>
            <div class="edit-profile__avatar community-settings__avatar">
                <span data-preview-fallback="avatar"><?= community_icon($community, 'xl') ?></span>
                <img class="community-icon community-icon--xl community-icon--img" src="data:," alt="" data-preview="avatar" hidden>
                <label class="edit-profile__avatar-btn" aria-label="Cambiar foto de la comunidad">
                    <?= icon('camera') ?>
                    <input class="sr-only" type="file" name="avatar" accept="<?= e($imageMimes) ?>" data-image-preview="avatar" data-max-bytes="<?= $maxImageBytes ?>">
                </label>
            </div>
        </div>

        <div class="card form-card">
            <p class="field__hint">Foto y portada: JPG, PNG, WEBP o GIF de hasta <?= (int) round($maxImageBytes / 1048576) ?> MB. Se recortan al centro (cuadrada la foto, 3:1 la portada).</p>
            <?php if (!empty($community['avatar_path']) || !empty($community['cover_path'])): ?>
                <div class="edit-profile__remove">
                    <?php foreach (['avatar' => 'Quitar foto', 'cover' => 'Quitar portada'] as $kind => $label): ?>
                        <?php if (!empty($community[$kind . '_path'])): ?>
                            <label class="checkbox">
                                <input type="checkbox" name="remove_<?= $kind ?>" value="1">
                                <span class="checkbox__box"><?= icon('check') ?></span>
                                <span><?= e($label) ?></span>
                            </label>
                        <?php endif; ?>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>

            <div class="field">
                <label class="field__label" for="cs-name">Nombre</label>
                <input class="input" id="cs-name" name="name" type="text" minlength="3" maxlength="<?= (int) $limits['community_name'] ?>" required
                    data-rule="required" value="<?= e($value('name')) ?>" data-char-count="#cs-name-count"<?= invalid_attrs($errors, 'name', 'cs-name') ?>>
                <?= field_error($errors, 'name', 'cs-name') ?>
                <p class="field__hint"><span id="cs-name-count"></span> · Dirección fija: <?= e(community_url($community)) ?></p>
            </div>
            <div class="field">
                <label class="field__label" for="cs-description">Descripción</label>
                <textarea class="input textarea" id="cs-description" name="description" rows="3" maxlength="<?= (int) $limits['community_description'] ?>" data-autosize
                    data-char-count="#cs-description-count"<?= invalid_attrs($errors, 'description', 'cs-description') ?>><?= e($value('description')) ?></textarea>
                <?= field_error($errors, 'description', 'cs-description') ?>
                <p class="field__hint"><span id="cs-description-count"></span></p>
            </div>
            <div class="field">
                <label class="field__label" for="cs-category">Categoría</label>
                <div class="select-wrap">
                    <?= icon('layout-grid') ?>
                    <select class="select" id="cs-category" name="category" required data-rule="required"<?= invalid_attrs($errors, 'category', 'cs-category') ?>>
                        <?php foreach ($categories as $option): ?>
                            <option value="<?= e($option) ?>" <?= $value('category') === $option ? 'selected' : '' ?>><?= e($option) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <?= field_error($errors, 'category', 'cs-category') ?>
            </div>
            <fieldset class="field community-form__visibility">
                <legend class="field__label">Visibilidad</legend>
                <?php foreach (Community::VISIBILITIES as $key => $label): ?>
                    <label class="choice-card">
                        <input type="radio" name="visibility" value="<?= e($key) ?>" <?= $value('visibility') === $key ? 'checked' : '' ?>>
                        <span class="choice-card__icon"><?= icon($key === 'private' ? 'lock' : 'globe') ?></span>
                        <span class="choice-card__text">
                            <strong><?= e($label) ?></strong>
                            <span><?= $key === 'private'
                                ? 'Solo los miembros ven las publicaciones; cada solicitud se aprueba.'
                                : 'Cualquiera ve las publicaciones y se une al instante. Al cambiar a pública se aceptan las solicitudes pendientes.' ?></span>
                        </span>
                    </label>
                <?php endforeach; ?>
                <?= field_error($errors, 'visibility', 'cs-visibility') ?>
            </fieldset>
        </div>
        <div class="form__actions">
            <button type="submit" class="btn btn--primary">Guardar cambios</button>
        </div>
    </form>

    <div class="card form-card danger-zone community-danger">
        <h3><?= icon('triangle-alert') ?> Zona de riesgo</h3>
        <details class="confirm-action" <?= isset($errors['transfer_username']) || isset($errors['transfer_password']) ? 'open' : '' ?>>
            <summary>
                <span>
                    <span class="setting-row__title">Transferir la comunidad</span>
                    <span class="setting-row__text">Otro miembro activo pasará a ser el administrador. Tú quedarás como moderador.</span>
                </span>
                <span class="btn btn--secondary btn--sm">Transferir</span>
            </summary>
            <form class="confirm-action__form" method="post" action="<?= e(url('api/communities.php')) ?>" novalidate data-validate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="transfer">
                <input type="hidden" name="community_id" value="<?= (int) $community['id'] ?>">
                <div class="field">
                    <label class="field__label" for="cs-transfer-user">Usuario del nuevo administrador</label>
                    <div class="input-wrap input-wrap--prefix">
                        <span class="input-wrap__prefix">@</span>
                        <input class="input" id="cs-transfer-user" name="transfer_username" type="text" maxlength="30" required data-rule="required"
                            autocomplete="off" spellcheck="false" autocapitalize="none" value="<?= e($old['transfer_username'] ?? '') ?>"<?= invalid_attrs($errors, 'transfer_username', 'cs-transfer-user') ?>>
                    </div>
                    <?= field_error($errors, 'transfer_username', 'cs-transfer-user') ?>
                </div>
                <?php View::partial('password-confirm', ['name' => 'transfer_password', 'id' => 'cs-transfer-password', 'errors' => $errors]); ?>
                <div class="form__actions">
                    <button type="submit" class="btn btn--secondary">Transferir administración</button>
                </div>
            </form>
        </details>

        <details class="confirm-action" <?= isset($errors['delete_confirm']) || isset($errors['delete_password']) ? 'open' : '' ?>>
            <summary>
                <span>
                    <span class="setting-row__title">Eliminar la comunidad</span>
                    <span class="setting-row__text">Se borrarán todas sus publicaciones, miembros e imágenes. No se puede deshacer.</span>
                </span>
                <span class="btn btn--danger btn--sm">Eliminar</span>
            </summary>
            <form class="confirm-action__form" method="post" action="<?= e(url('api/communities.php')) ?>" novalidate data-validate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="community_id" value="<?= (int) $community['id'] ?>">
                <div class="field">
                    <label class="field__label" for="cs-delete-confirm">Escribe <strong><?= e($community['slug']) ?></strong> para confirmar</label>
                    <input class="input" id="cs-delete-confirm" name="delete_confirm" type="text" required maxlength="60" autocomplete="off"
                        spellcheck="false" autocapitalize="none" data-rule="required"<?= invalid_attrs($errors, 'delete_confirm', 'cs-delete-confirm') ?>>
                    <?= field_error($errors, 'delete_confirm', 'cs-delete-confirm') ?>
                </div>
                <?php View::partial('password-confirm', ['name' => 'delete_password', 'id' => 'cs-delete-password', 'errors' => $errors]); ?>
                <div class="form__actions">
                    <button type="submit" class="btn btn--danger">Eliminar definitivamente</button>
                </div>
            </form>
        </details>
    </div>
    <script src="<?= e(asset('js/auth.js')) ?>" defer></script>
<?php endif; ?>

<script src="<?= e(asset('js/communities.js')) ?>" defer></script>
