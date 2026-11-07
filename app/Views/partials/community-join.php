<?php

use Trevix\Core\Auth;

/**
 * Botón de membresía de una comunidad según la relación de quien mira:
 * unirse / solicitar acceso / solicitud enviada (cancelar) / miembro (salir) / administrador / vetado.
 * Es un formulario real; communities.js lo envía con fetch y reemplaza el bloque con la respuesta.
 *
 * @var array $community
 * @var bool  $block      botón a todo el ancho (tarjetas)
 */
$block = !empty($block);
$membership = $community['membership'] ?? null;
$status = $membership['status'] ?? null;
$role = $membership['role'] ?? null;
$private = ($community['visibility'] ?? 'public') === 'private';
$size = $block ? ' btn--block btn--sm' : '';
$canWrite = Auth::check();
$disabled = $canWrite ? '' : ' disabled aria-disabled="true" data-tooltip="Inicia sesión para unirte"';
?>
<div class="community-join" data-community-join-box>
    <?php if ($status === 'active' && $role === 'owner'): ?>
        <a class="btn btn--secondary<?= $size ?>" href="<?= e(community_url($community, ['tab' => 'settings'])) ?>"><?= icon('crown') ?> Administrar</a>
    <?php elseif ($status === 'banned'): ?>
        <button type="button" class="btn btn--secondary<?= $size ?>" disabled><?= icon('ban') ?> No puedes unirte</button>
    <?php else: ?>
        <?php
        [$action, $label, $class, $iconName, $confirm] = match ($status) {
            'active'  => ['leave', $role === 'moderator' ? 'Moderador' : 'Miembro', 'btn--secondary', 'check', '¿Salir de ' . $community['name'] . '?' . ($private ? ' Para volver tendrás que pedir acceso de nuevo.' : '')],
            'pending' => ['leave', 'Solicitud enviada', 'btn--secondary', 'clock', '¿Cancelar tu solicitud para unirte a ' . $community['name'] . '?'],
            default   => ['join', $private ? 'Solicitar acceso' : 'Unirse', 'btn--primary', $private ? 'lock' : 'plus', ''],
        };
        $hover = match ($status) {
            'active'  => 'Salir',
            'pending' => 'Cancelar solicitud',
            default   => '',
        };
        ?>
        <form method="post" action="<?= e(url('api/communities.php')) ?>" data-community-join
            <?= $confirm !== '' ? 'data-join-confirm="' . e($confirm) . '" data-join-confirm-label="' . e($hover) . '"' : '' ?>>
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="<?= e($action) ?>">
            <input type="hidden" name="community_id" value="<?= (int) $community['id'] ?>">
            <input type="hidden" name="block" value="<?= $block ? '1' : '0' ?>">
            <button type="submit" class="<?= e('btn ' . $class . $size . ($hover !== '' ? ' community-join__toggle' : '')) ?>"<?= $disabled ?>
                <?= $hover !== '' ? 'data-hover-label="' . e($hover) . '"' : '' ?>>
                <?= icon($iconName) ?> <span><?= e($label) ?></span>
            </button>
        </form>
    <?php endif; ?>
</div>
