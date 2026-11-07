<?php

use Trevix\Core\Auth;

/**
 * Botón Seguir / Siguiendo / Solicitud enviada. Es un formulario real: funciona sin JavaScript
 * y follows.js lo envía con fetch y actualiza todos los botones de la misma persona en la página.
 *
 * @var array  $user    id, username, is_private y la relación (ver relation_of())
 * @var string $size    '' | 'sm'
 * @var string $idle    clase del botón cuando todavía no se sigue (btn--primary por defecto)
 * @var bool   $compact textos cortos para listas
 * @var bool   $block   ocupa todo el ancho
 */
$relation = relation_of($user);
$state = $relation['following'] ? 'following' : ($relation['requested'] ? 'requested' : 'none');
$private = !empty($user['is_private']);
$compact = $compact ?? false;
$idle = $idle ?? 'btn--primary';
$labels = [
    'none'      => $relation['follows_you'] ? 'Seguir también' : ($private ? ($compact ? 'Solicitar' : 'Solicitar seguir') : 'Seguir'),
    'following' => 'Siguiendo',
    'requested' => $compact ? 'Solicitado' : 'Solicitud enviada',
];
$actions = ['none' => 'follow', 'following' => 'unfollow', 'requested' => 'cancel'];
$classes = static fn (string $s) => cx('btn', $s === 'none' ? $idle : 'btn--secondary', [
    'btn--sm'    => ($size ?? '') === 'sm',
    'btn--block' => !empty($block),
]);
?>
<?php if (Auth::check() && (int) ($user['id'] ?? 0) === (int) Auth::id()): ?>
    <a class="<?= e(cx('btn', 'btn--secondary', ['btn--sm' => ($size ?? '') === 'sm', 'btn--block' => !empty($block)])) ?>" href="<?= e(profile_url($user)) ?>">Tu perfil</a>
<?php elseif (!Auth::check()): ?>
    <button type="button" class="<?= e($classes($state)) ?>" disabled aria-disabled="true" data-tooltip="Inicia sesión para seguir"><?= e($labels[$state]) ?></button>
<?php else: ?>
    <form class="follow-form" method="post" action="<?= e(url('api/follows.php')) ?>" data-follow-form
        data-user-id="<?= (int) $user['id'] ?>" data-username="<?= e($user['username']) ?>" data-private="<?= $private ? '1' : '0' ?>"
        data-state="<?= e($state) ?>" data-idle-class="<?= e($idle) ?>"
        data-label-none="<?= e($labels['none']) ?>" data-label-following="<?= e($labels['following']) ?>" data-label-requested="<?= e($labels['requested']) ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
        <input type="hidden" name="action" value="<?= e($actions[$state]) ?>">
        <button type="submit" class="<?= e($classes($state)) ?>" aria-pressed="<?= $state === 'none' ? 'false' : 'true' ?>"><?= e($labels[$state]) ?></button>
    </form>
<?php endif; ?>
