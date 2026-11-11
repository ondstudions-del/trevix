<?php
/**
 * @var string     $section
 * @var array      $sections
 * @var int        $passwordMin
 * @var array|null $viewer
 * @var bool       $panelOpen
 * @var array      $errors
 * @var array      $old
 * @var bool       $canEdit
 * @var bool       $isAdmin
 * @var array      $privacy ['blocked' => [...], 'pendingRequests' => int]
 * @var array      $notifyFields campo => [título, texto]
 */
$current = $sections[$section];
$isPendingSection = $current['phase'] > 5;
$messagePrivacy = $viewer['message_privacy'] ?? 'everyone';
$disabledUnlessUser = $canEdit ? '' : ' disabled aria-disabled="true" data-tooltip="' . e(t('Inicia sesión para guardar cambios')) . '"';
$verified = !empty($viewer['email_verified_at']);
$sectionUrl = static fn (string $key): string => url('settings.php', ['section' => $key]);
$passwordField = static function (string $name, string $id, string $label, array $errors): string {
    return '<div class="field"><label class="field__label" for="' . e($id) . '">' . e($label) . '</label>'
        . '<div class="input-wrap">' . icon('lock')
        . '<input class="input" id="' . e($id) . '" name="' . e($name) . '" type="password" autocomplete="current-password" required maxlength="200" data-rule="required"'
        . invalid_attrs($errors, $name, $id) . '>'
        . '<button type="button" class="input-wrap__action" data-toggle-password aria-label="' . e(t('Mostrar contraseña')) . '" aria-pressed="false">'
        . icon('eye', 'when-hidden') . icon('eye-off', 'when-visible') . '</button></div>'
        . field_error($errors, $name, $id) . '</div>';
};
$toggle = static function (string $name, string $title, string $text, bool $checked = false, string $attrs = ''): string {
    return '<div class="setting-row"><div><p class="setting-row__title">' . e($title) . '</p>'
        . '<p class="setting-row__text">' . e($text) . '</p></div>'
        . '<label class="switch"><input type="checkbox" role="switch" name="' . e($name) . '" value="1"' . ($checked ? ' checked' : '') . ' ' . $attrs . '>'
        . '<span class="switch__track" aria-hidden="true"></span><span class="sr-only">' . e($title) . '</span></label></div>';
};
?>
<div class="<?= cx('settings', ['settings--panel-open' => $panelOpen]) ?>">
    <nav class="settings__nav" aria-label="<?= e(t('Secciones de configuración')) ?>">
        <h1 class="settings__title"><?= e(t('Configuración')) ?></h1>
        <?php foreach ($sections as $key => $item): ?>
            <a class="<?= cx('settings__link', ['is-active' => $section === $key]) ?>" href="<?= e($sectionUrl($key)) ?>"
                <?= $section === $key ? 'aria-current="page"' : '' ?>>
                <?= icon($item['icon']) ?>
                <span><?= e(t($item['label'])) ?></span>
                <?= icon('chevron-right', 'settings__chevron') ?>
            </a>
        <?php endforeach; ?>
        <?php if ($canEdit): ?>
            <?php foreach (\Trevix\Controllers\WalletController::TABS as $key => $item): ?>
                <?php if ($key === 'subscriptions') continue; ?>
                <a class="settings__link" href="<?= e(url('wallet.php', ['tab' => $key === 'wallet' ? null : $key])) ?>">
                    <?= icon($item['icon']) ?>
                    <span><?= e(t($item['label'])) ?></span>
                    <?= icon('chevron-right', 'settings__chevron') ?>
                </a>
            <?php endforeach; ?>
            <form method="post" action="<?= e(url('logout.php')) ?>">
                <?= csrf_field() ?>
                <button type="submit" class="settings__link settings__link--danger"><?= icon('log-out') ?><span><?= e(t('Cerrar sesión')) ?></span></button>
            </form>
        <?php endif; ?>
    </nav>

    <section class="settings__panel" aria-labelledby="settings-heading">
        <header class="settings__panel-head">
            <a class="icon-btn settings__back" href="<?= e(url('settings.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
            <h2 id="settings-heading"><?= e(t($current['label'])) ?></h2>
        </header>

        <?php if ($isPendingSection): ?>
            <div class="alert alert--info">
                <?= icon('info') ?>
                <p><?= t('Estas opciones se guardarán en el servidor a partir de la {phase}.', ['phase' => '<strong>' . e(t('Fase {n}', ['n' => (int) $current['phase']])) . '</strong>']) ?></p>
            </div>
        <?php endif; ?>

        <?php if ($section === 'account'): ?>
            <form class="form card form-card" method="post" action="<?= e($sectionUrl('account')) ?>" novalidate data-validate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="account">
                <div class="field">
                    <label class="field__label" for="st-email"><?= e(t('Correo electrónico')) ?></label>
                    <div class="input-wrap">
                        <?= icon('mail') ?>
                        <input class="input" id="st-email" name="email" type="email" autocomplete="email" maxlength="190" required data-rule="email"
                            value="<?= e($old['email'] ?? $viewer['email'] ?? '') ?>" placeholder="<?= e(t('tu@correo.com')) ?>" spellcheck="false" autocapitalize="none"
                            data-original="<?= e($viewer['email'] ?? '') ?>"<?= invalid_attrs($errors, 'email', 'st-email') ?>>
                    </div>
                    <?= field_error($errors, 'email', 'st-email') ?>
                    <p class="field__hint"><?= e(t('Si lo cambias, te enviaremos un enlace a la nueva dirección. El cambio se aplica cuando lo confirmes.')) ?></p>
                </div>
                <div class="field">
                    <label class="field__label" for="st-username"><?= e(t('Nombre de usuario')) ?></label>
                    <div class="input-wrap input-wrap--prefix">
                        <span class="input-wrap__prefix">@</span>
                        <input class="input" id="st-username" name="username" type="text" minlength="3" maxlength="30" pattern="[a-z0-9_.]{3,30}" required
                            data-rule="username" value="<?= e($old['username'] ?? $viewer['username'] ?? '') ?>" spellcheck="false" autocapitalize="none"
                            data-username-input<?= invalid_attrs($errors, 'username', 'st-username') ?>>
                    </div>
                    <?= field_error($errors, 'username', 'st-username') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="st-phone"><?= e(t('Número de teléfono')) ?> <span class="field__optional"><?= e(t('(opcional)')) ?></span></label>
                    <div class="input-wrap">
                        <?= icon('phone') ?>
                        <input class="input" id="st-phone" name="phone" type="tel" autocomplete="tel" maxlength="20" inputmode="tel"
                            value="<?= e($old['phone'] ?? $viewer['phone'] ?? '') ?>" placeholder="+57 300 123 4567"<?= invalid_attrs($errors, 'phone', 'st-phone') ?>>
                    </div>
                    <?= field_error($errors, 'phone', 'st-phone') ?>
                    <p class="field__hint"><?= e(t('Es privado: no aparece en tu perfil. Solo lo ve el equipo de TREVIX si necesita contactarte.')) ?></p>
                </div>
                <div data-email-password <?= isset($errors['current_password']) ? '' : 'hidden' ?>>
                    <?= $passwordField('current_password', 'st-current-password', t('Contraseña actual (necesaria para cambiar el correo)'), $errors) ?>
                </div>
                <div class="form__actions">
                    <button type="submit" class="btn btn--primary"<?= $disabledUnlessUser ?>><?= e(t('Guardar')) ?></button>
                </div>
            </form>

            <div class="card form-card">
                <div class="setting-row">
                    <div>
                        <p class="setting-row__title"><?= icon('mail') ?> <?= e(t('Confirmación del correo')) ?></p>
                        <p class="setting-row__text">
                            <?= e($verified
                                ? t('Tu correo está confirmado. Lo usaremos para recuperar tu cuenta y avisarte de cambios importantes.')
                                : t('Confirma tu correo para poder recuperar tu cuenta si olvidas la contraseña.')) ?>
                        </p>
                    </div>
                    <div class="setting-row__status">
                        <span class="<?= $verified ? 'chip chip--success' : 'chip chip--warning' ?>"><?= e($verified ? t('Confirmado') : t('Sin confirmar')) ?></span>
                        <?php if (!$verified): ?>
                            <form method="post" action="<?= e($sectionUrl('account')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="resend_verification">
                                <button type="submit" class="btn btn--secondary btn--sm"<?= $disabledUnlessUser ?>><?= e(t('Reenviar enlace')) ?></button>
                            </form>
                        <?php endif; ?>
                    </div>
                </div>
            </div>

            <div class="card form-card">
                <div class="setting-row">
                    <div>
                        <p class="setting-row__title"><?= icon('globe') ?> <?= e(t('Idioma')) ?></p>
                        <p class="setting-row__text"><?= e(t('El idioma de los menús, botones y avisos de TREVIX. Se guarda en tu cuenta.')) ?></p>
                    </div>
                    <?php \Trevix\Core\View::partial('lang-switch', ['class' => 'lang-switch--card']); ?>
                </div>
            </div>

            <?php if ($canEdit): ?>
                <div class="card form-card">
                    <div class="setting-row">
                        <div>
                            <p class="setting-row__title"><?= icon('scale') ?> <?= e(t('Advertencias y apelaciones')) ?></p>
                            <p class="setting-row__text"><?= e(t('Revisa las advertencias de tu cuenta y apela si crees que alguna es un error.')) ?></p>
                        </div>
                        <a class="btn btn--secondary btn--sm" href="<?= e(url('appeals.php')) ?>"><?= e(t('Ver')) ?></a>
                    </div>
                </div>
            <?php endif; ?>

            <div class="card form-card danger-zone">
                <h3><?= icon('triangle-alert') ?> <?= e(t('Zona de riesgo')) ?></h3>
                <?php if ($isAdmin): ?>
                    <p class="setting-row__text"><?= e(t('Las cuentas de administración no se pueden desactivar ni eliminar desde aquí, para que la plataforma no se quede sin acceso.')) ?></p>
                <?php else: ?>
                    <details class="confirm-action" <?= isset($errors['deactivate_password']) ? 'open' : '' ?>>
                        <summary>
                            <span>
                                <span class="setting-row__title"><?= e(t('Desactivar cuenta')) ?></span>
                                <span class="setting-row__text"><?= e(t('Tu perfil y publicaciones se ocultarán hasta que vuelvas a iniciar sesión.')) ?></span>
                            </span>
                            <span class="btn btn--secondary btn--sm"><?= e(t('Desactivar')) ?></span>
                        </summary>
                        <form class="confirm-action__form" method="post" action="<?= e($sectionUrl('account')) ?>" novalidate data-validate>
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="deactivate">
                            <?= $passwordField('deactivate_password', 'st-deactivate-password', t('Confirma con tu contraseña'), $errors) ?>
                            <div class="form__actions">
                                <button type="submit" class="btn btn--secondary"<?= $disabledUnlessUser ?>><?= e(t('Desactivar mi cuenta')) ?></button>
                            </div>
                        </form>
                    </details>

                    <details class="confirm-action" <?= isset($errors['delete_password']) || isset($errors['delete_confirm']) ? 'open' : '' ?>>
                        <summary>
                            <span>
                                <span class="setting-row__title"><?= e(t('Eliminar cuenta')) ?></span>
                                <span class="setting-row__text"><?= e(t('Elimina de forma permanente tu cuenta y todo tu contenido. No se puede deshacer.')) ?></span>
                            </span>
                            <span class="btn btn--danger btn--sm"><?= e(t('Eliminar')) ?></span>
                        </summary>
                        <form class="confirm-action__form" method="post" action="<?= e($sectionUrl('account')) ?>" novalidate data-validate>
                            <?= csrf_field() ?>
                            <input type="hidden" name="action" value="delete">
                            <div class="field">
                                <label class="field__label" for="st-delete-confirm"><?= t('Escribe {username} sin la arroba para confirmar', ['username' => '<strong>@' . e($viewer['username'] ?? '') . '</strong>']) ?></label>
                                <input class="input" id="st-delete-confirm" name="delete_confirm" type="text" required maxlength="30" autocomplete="off"
                                    spellcheck="false" autocapitalize="none" data-rule="required"<?= invalid_attrs($errors, 'delete_confirm', 'st-delete-confirm') ?>>
                                <?= field_error($errors, 'delete_confirm', 'st-delete-confirm') ?>
                            </div>
                            <?= $passwordField('delete_password', 'st-delete-password', t('Confirma con tu contraseña'), $errors) ?>
                            <div class="form__actions">
                                <button type="submit" class="btn btn--danger"<?= $disabledUnlessUser ?>><?= e(t('Eliminar definitivamente')) ?></button>
                            </div>
                        </form>
                    </details>
                <?php endif; ?>
            </div>

        <?php elseif ($section === 'security'): ?>
            <form class="form card form-card" method="post" action="<?= e($sectionUrl('security')) ?>" novalidate data-validate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="password">
                <h3 class="form-card__title"><?= e(t('Cambiar contraseña')) ?></h3>
                <?= $passwordField('current_password', 'current-password', t('Contraseña actual'), $errors) ?>
                <div class="field">
                    <label class="field__label" for="new-password"><?= e(t('Nueva contraseña')) ?></label>
                    <div class="input-wrap">
                        <?= icon('key-round') ?>
                        <input class="input" id="new-password" name="password" type="password" autocomplete="new-password" required
                            minlength="<?= $passwordMin ?>" maxlength="128" data-rule="password" data-strength-meter="#password-strength"<?= invalid_attrs($errors, 'password', 'new-password') ?>>
                        <button type="button" class="input-wrap__action" data-toggle-password aria-label="<?= e(t('Mostrar contraseña')) ?>" aria-pressed="false">
                            <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                        </button>
                    </div>
                    <div class="strength" id="password-strength" data-level="0">
                        <div class="strength__bars" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
                        <span class="strength__label" aria-live="polite"><?= e(t('Escribe una contraseña')) ?></span>
                    </div>
                    <ul class="requirements" data-requirements-for="new-password">
                        <li data-req="length"><?= icon('check') ?> <?= e(t('Al menos {n} caracteres', ['n' => $passwordMin])) ?></li>
                        <li data-req="case"><?= icon('check') ?> <?= e(t('Mayúsculas y minúsculas')) ?></li>
                        <li data-req="number"><?= icon('check') ?> <?= e(t('Al menos un número')) ?></li>
                        <li data-req="symbol"><?= icon('check') ?> <?= e(t('Al menos un símbolo')) ?></li>
                    </ul>
                    <?= field_error($errors, 'password', 'new-password') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="confirm-password"><?= e(t('Confirmar nueva contraseña')) ?></label>
                    <div class="input-wrap">
                        <?= icon('lock-keyhole') ?>
                        <input class="input" id="confirm-password" name="password_confirmation" type="password" autocomplete="new-password" required
                            maxlength="128" data-rule="confirm" data-confirm="#new-password"<?= invalid_attrs($errors, 'password_confirmation', 'confirm-password') ?>>
                    </div>
                    <?= field_error($errors, 'password_confirmation', 'confirm-password') ?>
                </div>
                <p class="field__hint"><?= e(t('Al cambiarla se cerrará la sesión en tus otros dispositivos y te enviaremos un aviso por correo.')) ?></p>
                <div class="form__actions">
                    <button type="submit" class="btn btn--primary"<?= $disabledUnlessUser ?>><?= e(t('Actualizar contraseña')) ?></button>
                </div>
            </form>

            <div class="card form-card">
                <h3 class="form-card__title"><?= e(t('Sesiones')) ?></h3>
                <div class="setting-row">
                    <div class="session-item">
                        <span class="session-item__icon"><?= icon('monitor') ?></span>
                        <div>
                            <p class="setting-row__title"><?= e(t('Este dispositivo')) ?></p>
                            <p class="setting-row__text"><?= e(t('Sesión actual · protegida con cookie HttpOnly')) ?></p>
                        </div>
                    </div>
                    <span class="chip chip--success"><?= e(t('Activa')) ?></span>
                </div>
                <details class="confirm-action" <?= isset($errors['sessions_password']) ? 'open' : '' ?>>
                    <summary>
                        <span>
                            <span class="setting-row__title"><?= e(t('Cerrar las demás sesiones')) ?></span>
                            <span class="setting-row__text"><?= e(t('Sal de TREVIX en cualquier otro navegador o dispositivo donde hayas iniciado sesión.')) ?></span>
                        </span>
                        <span class="btn btn--secondary btn--sm"><?= e(t('Cerrar sesiones')) ?></span>
                    </summary>
                    <form class="confirm-action__form" method="post" action="<?= e($sectionUrl('security')) ?>" novalidate data-validate>
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="sessions">
                        <?= $passwordField('sessions_password', 'st-sessions-password', t('Confirma con tu contraseña'), $errors) ?>
                        <div class="form__actions">
                            <button type="submit" class="btn btn--secondary"<?= $disabledUnlessUser ?>><?= e(t('Cerrar las demás sesiones')) ?></button>
                        </div>
                    </form>
                </details>
            </div>

        <?php elseif ($section === 'privacy'): ?>
            <form class="form card form-card" method="post" action="<?= e($sectionUrl('privacy')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="privacy">
                <fieldset class="fieldset"<?= $canEdit ? '' : ' disabled' ?>>
                    <legend class="sr-only"><?= e(t('Privacidad de la cuenta')) ?></legend>
                    <?= $toggle('is_private', t('Cuenta privada'), t('Solo tus seguidores ven tus publicaciones, seguidores y seguidos. Las nuevas personas deberán enviarte una solicitud. Si vuelves a hacerla pública, se aprobarán las solicitudes pendientes.'), !empty($viewer['is_private'])) ?>
                    <?php if ($privacy['pendingRequests'] > 0): ?>
                        <p class="form-card__lead">
                            <?= icon('user-round-plus') ?>
                            <a href="<?= e(url('notifications.php', ['filter' => 'requests'])) ?>">
                                <?= e(tn((int) $privacy['pendingRequests'], 'Tienes {n} solicitud de seguimiento pendiente', 'Tienes {n} solicitudes de seguimiento pendientes')) ?>
                            </a>
                        </p>
                    <?php endif; ?>
                    <?= $toggle('show_activity', t('Mostrar estado de actividad'), t('Las personas con las que conversas verán cuándo estás en línea. Si lo desactivas, tampoco verás el estado de los demás.'), !isset($viewer['show_activity']) || !empty($viewer['show_activity'])) ?>
                    <?= $toggle('read_receipts', t('Confirmación de lectura'), t('Los demás verán cuándo leíste sus mensajes. Si la desactivas, tampoco verás quién leyó los tuyos.'), !isset($viewer['read_receipts']) || !empty($viewer['read_receipts'])) ?>
                    <div class="setting-row">
                        <div>
                            <p class="setting-row__title"><?= e(t('¿Quién puede enviarte mensajes?')) ?></p>
                            <p class="setting-row__text"><?= e(t('Controla quién puede iniciar una conversación contigo. Siempre podrás responder en las conversaciones en las que ya escribiste.')) ?></p>
                        </div>
                        <div class="select-wrap select-wrap--sm">
                            <select class="select" name="message_privacy" aria-label="<?= e(t('Quién puede enviarte mensajes')) ?>">
                                <?php foreach (['everyone' => t('Todos'), 'following' => t('Personas que sigo'), 'nobody' => t('Nadie')] as $value => $label): ?>
                                    <option value="<?= $value ?>" <?= $messagePrivacy === $value ? 'selected' : '' ?>><?= e($label) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    <div class="form__actions">
                        <button type="submit" class="btn btn--primary"<?= $disabledUnlessUser ?>><?= e(t('Guardar')) ?></button>
                    </div>
                </fieldset>
            </form>

            <section class="card form-card" aria-labelledby="blocked-heading">
                <h3 class="form-card__title" id="blocked-heading"><?= e(t('Cuentas bloqueadas')) ?></h3>
                <?php if ($privacy['blocked'] === []): ?>
                    <p class="setting-row__text"><?= e(t('No has bloqueado a nadie. Puedes bloquear una cuenta desde el menú de su perfil.')) ?></p>
                <?php else: ?>
                    <ul class="user-list">
                        <?php foreach ($privacy['blocked'] as $blocked): ?>
                            <li class="user-row">
                                <a class="user-row__link" href="<?= e(profile_url($blocked)) ?>">
                                    <?= avatar($blocked, 'md') ?>
                                    <span class="user-row__text">
                                        <span class="user-row__name"><?= e($blocked['display_name']) ?></span>
                                        <span class="user-row__meta">@<?= e($blocked['username']) ?> · <?= e(t('desde el {date}', ['date' => full_date($blocked['blocked_at'], false)])) ?></span>
                                    </span>
                                </a>
                                <form method="post" action="<?= e(url('api/blocks.php')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="unblock">
                                    <input type="hidden" name="user_id" value="<?= (int) $blocked['id'] ?>">
                                    <button type="submit" class="btn btn--sm btn--secondary"><?= e(t('Desbloquear')) ?></button>
                                </form>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                <?php endif; ?>
            </section>

        <?php elseif ($section === 'notifications'): ?>
            <form class="form card form-card" method="post" action="<?= e($sectionUrl('notifications')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="notifications">
                <fieldset class="fieldset"<?= $canEdit ? '' : ' disabled' ?>>
                    <legend class="sr-only"><?= e(t('Notificaciones')) ?></legend>
                    <p class="form-card__lead"><?= icon('bell') ?> <?= e(t('Elige de qué actividad quieres recibir avisos en TREVIX.')) ?></p>
                    <?php foreach ($notifyFields as $field => [$title, $text]): ?>
                        <?= $toggle($field, t($title), t($text), !isset($viewer[$field]) || !empty($viewer[$field])) ?>
                    <?php endforeach; ?>
                    <div class="form__actions">
                        <button type="submit" class="btn btn--primary"<?= $disabledUnlessUser ?>><?= e(t('Guardar')) ?></button>
                    </div>
                </fieldset>
            </form>

        <?php else: ?>
            <div class="card form-card" data-appearance>
                <p class="form-card__lead"><?= icon('monitor') ?> <?= e(t('Estas preferencias se aplican de inmediato y se guardan en este dispositivo.')) ?></p>
                <?= $toggle('reduce_motion', t('Reducir animaciones'), t('Minimiza transiciones y movimientos en toda la interfaz.'), false, 'data-pref="reduceMotion"') ?>
                <div class="setting-row setting-row--stack">
                    <div>
                        <p class="setting-row__title"><?= e(t('Tamaño del texto')) ?></p>
                        <p class="setting-row__text"><?= e(t('Ajusta el tamaño de la letra en TREVIX.')) ?></p>
                    </div>
                    <div class="segmented segmented--block" role="radiogroup" aria-label="<?= e(t('Tamaño del texto')) ?>">
                        <?php foreach (['normal' => t('Normal'), 'large' => t('Grande'), 'xlarge' => t('Muy grande')] as $value => $label): ?>
                            <label class="segmented__option">
                                <input type="radio" name="font_size" value="<?= e($value) ?>" data-pref="fontSize" <?= $value === 'normal' ? 'checked' : '' ?>>
                                <span><?= e($label) ?></span>
                            </label>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>
        <?php endif; ?>
    </section>
</div>
<?php if (in_array($section, ['account', 'security'], true)): ?>
    <script src="<?= e(asset('js/auth.js')) ?>" defer></script>
<?php endif; ?>
