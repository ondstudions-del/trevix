<?php

use Trevix\Core\View;
use Trevix\Services\Giphy;

/**
 * @var array      $conversations  bandeja (Conversation::inbox)
 * @var array|null $active         conversación abierta (Conversation::findFor)
 * @var array      $messages       mensajes de la conversación abierta, en orden cronológico
 * @var bool       $hasOlder
 * @var array|null $draftTo        persona a la que se escribe por primera vez
 * @var string|null $blockedReason motivo por el que no se puede escribir
 * @var array|null $newSearch      ['term' => string, 'users' => list] para "Nuevo mensaje"
 * @var int        $viewerId
 * @var int        $maxBody
 */
$before = $before ?? 0;
$partner = $active['user'] ?? $draftTo;
$hasChat = $partner !== null;
$isGroup = ($active['type'] ?? 'direct') === 'group';
$showPanel = $hasChat || $newSearch !== null;

$lastMessage = $messages !== [] ? end($messages) : null;
$lastMine = $lastMessage !== null && $lastMessage['deleted_at'] === null && (int) $lastMessage['sender_id'] === $viewerId;
$seen = $lastMine && $active !== null && (int) ($active['partner_last_read'] ?? 0) >= (int) $lastMessage['id'];
$imageRules = (array) \Trevix\Core\Config::get('app.uploads.image');
?>
<div class="<?= cx('messenger', ['has-active' => $showPanel]) ?>">
    <aside class="messenger__list" aria-label="Conversaciones">
        <header class="messenger__list-head">
            <h1 class="messenger__title">Mensajes</h1>
            <?php if ($viewerId > 0): ?>
                <a class="icon-btn" href="<?= e(url('messages.php', ['new' => 1])) ?>" aria-label="Nuevo mensaje" data-tooltip="Nuevo mensaje"><?= icon('message-square-plus') ?></a>
            <?php else: ?>
                <button type="button" class="icon-btn" aria-label="Nuevo mensaje" disabled data-tooltip="Inicia sesión para escribir"><?= icon('message-square-plus') ?></button>
            <?php endif; ?>
        </header>
        <?php if ($conversations !== []): ?>
            <div class="search-field search-field--sm">
                <?= icon('search') ?>
                <label class="sr-only" for="conv-filter">Filtrar conversaciones</label>
                <input id="conv-filter" type="search" placeholder="Buscar conversaciones" autocomplete="off" data-filter-input="#conv-items">
            </div>
        <?php else: ?>
            <p class="messenger__empty">Aún no tienes conversaciones. Escribe a alguien con el botón <strong>Nuevo mensaje</strong> o desde su perfil.</p>
        <?php endif; ?>

        <ul class="conv-list" id="conv-items">
            <?php foreach ($conversations as $conversation): ?>
                <?php $isActive = $active !== null && $active['id'] === $conversation['id']; ?>
                <li data-filter-text="<?= e(mb_strtolower($conversation['user']['display_name'] . ' ' . $conversation['user']['username'])) ?>">
                    <a class="<?= cx('conv', ['is-active' => $isActive, 'is-unread' => $conversation['unread'] > 0]) ?>"
                        href="<?= e(url('messages.php', ['c' => $conversation['id']])) ?>" <?= $isActive ? 'aria-current="page"' : '' ?>>
                        <span class="conv__avatar">
                            <?= avatar($conversation['user'], 'md') ?>
                            <?php if ($conversation['online']): ?><span class="presence" aria-label="En línea"></span><?php endif; ?>
                        </span>
                        <span class="conv__text">
                            <span class="conv__top">
                                <span class="conv__name"><?= e($conversation['user']['display_name']) ?></span>
                                <span class="conv__time"><?= time_tag((string) $conversation['last_message_at']) ?></span>
                            </span>
                            <span class="conv__preview">
                                <?php if ($conversation['muted']): ?><?= icon('bell-off', 'conv__muted', 'Silenciada') ?><?php endif; ?>
                                <?= e((string) $conversation['preview']) ?>
                            </span>
                        </span>
                        <?php if ($conversation['unread'] > 0): ?>
                            <span class="badge-count badge-count--static" aria-label="<?= (int) $conversation['unread'] ?> sin leer"><?= $conversation['unread'] > 99 ? '99+' : (int) $conversation['unread'] ?></span>
                        <?php endif; ?>
                    </a>
                </li>
            <?php endforeach; ?>
        </ul>
    </aside>

    <section class="messenger__chat" aria-label="<?= $newSearch !== null ? 'Nuevo mensaje' : 'Conversación' ?>">
        <?php if ($newSearch !== null): ?>
            <header class="chat__head">
                <a class="icon-btn chat__back" href="<?= e(url('messages.php')) ?>" aria-label="Volver a conversaciones"><?= icon('arrow-left') ?></a>
                <h2 class="chat__name">Nuevo mensaje</h2>
            </header>
            <div class="new-message">
                <form class="new-message__search" method="get" action="<?= e(url('messages.php')) ?>" role="search">
                    <input type="hidden" name="new" value="1">
                    <div class="search-field">
                        <?= icon('search') ?>
                        <label class="sr-only" for="new-message-q">Buscar personas</label>
                        <input id="new-message-q" type="search" name="q" value="<?= e($newSearch['term']) ?>" maxlength="60"
                            placeholder="Busca por nombre o @usuario" autocomplete="off" autofocus>
                    </div>
                    <button type="submit" class="btn btn--primary btn--sm">Buscar</button>
                </form>
                <p class="new-message__label"><?= $newSearch['term'] !== '' ? 'Resultados' : 'Personas que sigues' ?></p>
                <?php if ($newSearch['users'] === []): ?>
                    <p class="messenger__empty">
                        <?= $newSearch['term'] !== ''
                            ? 'No encontramos a nadie con «' . e($newSearch['term']) . '».'
                            : 'Aún no sigues a nadie. Busca a una persona por su nombre o usuario.' ?>
                    </p>
                <?php else: ?>
                    <ul class="user-list">
                        <?php foreach ($newSearch['users'] as $person): ?>
                            <li class="user-row">
                                <a class="user-row__link" href="<?= e(profile_url($person)) ?>">
                                    <?= avatar($person, 'md') ?>
                                    <span class="user-row__text">
                                        <span class="user-row__name"><?= e($person['display_name']) ?></span>
                                        <span class="user-row__meta">@<?= e($person['username']) ?></span>
                                    </span>
                                </a>
                                <a class="btn btn--sm btn--secondary" href="<?= e(url('messages.php', ['to' => $person['username']])) ?>"><?= icon('send') ?> Escribir</a>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                <?php endif; ?>
            </div>

        <?php elseif ($hasChat): ?>
            <?php
            $available = $active === null || $active['available'];
            $online = $active['online'] ?? false;
            $linkProfile = $available && !$isGroup;
            $groupStatus = $isGroup ? 'Grupo · ' . (int) ($active['group']['members_count'] ?? 0) . ' participantes' : '';
            ?>
            <header class="chat__head">
                <a class="icon-btn chat__back" href="<?= e(url('messages.php')) ?>" aria-label="Volver a conversaciones"><?= icon('arrow-left') ?></a>
                <?php if ($linkProfile): ?>
                    <a class="chat__who" href="<?= e(profile_url($partner)) ?>">
                <?php else: ?>
                    <span class="chat__who">
                <?php endif; ?>
                    <span class="conv__avatar">
                        <?= avatar($partner, 'md') ?>
                        <span class="presence" data-chat-presence <?= $online ? '' : 'hidden' ?>></span>
                    </span>
                    <span>
                        <span class="chat__name"><?= e($partner['display_name']) ?> <?= !empty($partner['is_verified']) ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?></span>
                        <?php $offline = $isGroup ? $groupStatus : ($available ? '@' . $partner['username'] : 'Cuenta no disponible'); ?>
                        <span class="chat__status" data-chat-status data-offline="<?= e($offline) ?>">
                            <?= $online ? 'En línea' : e($offline) ?>
                        </span>
                    </span>
                <?= $linkProfile ? '</a>' : '</span>' ?>
                <?php if ($active !== null && $viewerId > 0): ?>
                    <div class="dropdown" data-dropdown>
                        <button type="button" class="icon-btn" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false" aria-label="Opciones de la conversación"><?= icon('ellipsis') ?></button>
                        <div class="dropdown__menu" role="menu" hidden>
                            <?php if ($linkProfile): ?>
                                <a class="dropdown__item" role="menuitem" href="<?= e(profile_url($partner)) ?>"><?= icon('user') ?> Ver perfil</a>
                            <?php endif; ?>
                            <form method="post" action="<?= e(url('api/messages.php')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="mute">
                                <input type="hidden" name="c" value="<?= (int) $active['id'] ?>">
                                <input type="hidden" name="muted" value="<?= $active['muted'] ? '0' : '1' ?>">
                                <button type="submit" class="dropdown__item" role="menuitem">
                                    <?= $active['muted'] ? icon('bell') . ' Activar avisos' : icon('bell-off') . ' Silenciar conversación' ?>
                                </button>
                            </form>
                        </div>
                    </div>
                <?php endif; ?>
            </header>

            <div class="chat__messages" data-chat-scroll aria-live="polite"
                <?php if ($active !== null && $viewerId > 0 && $before === 0): ?>
                    data-chat-poll="<?= e(url('api/messages.php')) ?>" data-conversation="<?= (int) $active['id'] ?>"
                    data-last-id="<?= $lastMessage !== null ? (int) $lastMessage['id'] : 0 ?>"
                    data-first-id="<?= $messages !== [] ? (int) $messages[0]['id'] : 0 ?>"
                <?php endif; ?>>
                <?php if ($hasOlder): ?>
                    <div class="chat__older">
                        <a class="btn btn--ghost btn--sm" href="<?= e(url('messages.php', ['c' => $active['id'], 'before' => (int) $messages[0]['id']])) ?>" data-chat-older>Cargar mensajes anteriores</a>
                    </div>
                <?php else: ?>
                    <div class="chat__intro">
                        <?= avatar($partner, 'lg') ?>
                        <strong><?= e($partner['display_name']) ?></strong>
                        <?php if ($isGroup): ?>
                            <span><?= e($groupStatus) ?></span>
                            <?php if (($active['group']['description'] ?? '') !== ''): ?>
                                <span><?= e((string) $active['group']['description']) ?></span>
                            <?php endif; ?>
                        <?php elseif ($available): ?>
                            <span>@<?= e($partner['username']) ?></span>
                        <?php endif; ?>
                        <?php if (!empty($active['e2ee'])): ?>
                            <span><?= icon('lock') ?> Cifrado de extremo a extremo: los mensajes cifrados solo se leen en la app TREVIX.</span>
                        <?php elseif ($messages === []): ?>
                            <span>Los mensajes privados solo los ven los participantes de la conversación.</span>
                        <?php endif; ?>
                    </div>
                <?php endif; ?>
                <div class="chat__list" data-chat-list>
                    <?php foreach ($messages as $message): ?>
                        <?php View::partial('message', [
                            'message' => $message, 'viewerId' => $viewerId, 'isGroup' => $isGroup,
                            'partnerName' => $isGroup ? '' : (string) (($active['nickname'] ?? null) ?: $active['user']['display_name']),
                        ]); ?>
                    <?php endforeach; ?>
                </div>
                <p class="chat__seen" data-chat-seen data-seen-id="<?= (int) ($active['partner_last_read'] ?? 0) ?>" <?= $seen ? '' : 'hidden' ?>><?= icon('check-check') ?> Visto</p>
                <?php if ($before > 0): ?>
                    <div class="chat__older">
                        <a class="btn btn--ghost btn--sm" href="<?= e(url('messages.php', ['c' => $active['id']])) ?>">Ir a los mensajes recientes</a>
                    </div>
                <?php endif; ?>
            </div>

            <?php if ($blockedReason !== null): ?>
                <p class="chat__blocked"><?= icon('lock') ?> <?= e($blockedReason) ?></p>
            <?php else: ?>
                <form class="chat__composer" method="post" action="<?= e(url('api/messages.php')) ?>" enctype="multipart/form-data" data-chat-form>
                    <?= csrf_field() ?>
                    <input type="hidden" name="action" value="send">
                    <?php if ($active !== null): ?>
                        <input type="hidden" name="c" value="<?= (int) $active['id'] ?>">
                    <?php else: ?>
                        <input type="hidden" name="to" value="<?= e($partner['username']) ?>">
                    <?php endif; ?>
                    <div class="chat__attachment" data-chat-attachment hidden>
                        <img alt="" data-chat-attachment-img>
                        <span data-chat-attachment-name></span>
                        <button type="button" class="icon-btn icon-btn--sm" aria-label="Quitar imagen" data-chat-attachment-clear><?= icon('x') ?></button>
                    </div>
                    <?php View::partial('gif-field'); ?>
                    <div class="voice-recorder" data-voice-recorder hidden>
                        <span class="voice-recorder__dot" aria-hidden="true"></span>
                        <span class="voice-recorder__label" data-voice-label>Grabando… <span class="voice-recorder__time" data-voice-time>0:00</span></span>
                        <audio controls preload="metadata" data-voice-preview hidden></audio>
                        <button type="button" class="icon-btn icon-btn--sm" data-voice-cancel aria-label="Descartar nota de voz" data-tooltip="Descartar"><?= icon('trash-2') ?></button>
                        <button type="button" class="btn btn--secondary btn--sm" data-voice-stop><?= icon('square') ?> Detener</button>
                    </div>
                    <label class="icon-btn icon-btn--accent chat__attach" for="chat-image" data-tooltip="Adjuntar imagen">
                        <?= icon('image') ?><span class="sr-only">Adjuntar imagen</span>
                    </label>
                    <?php if (Giphy::enabled()): ?>
                        <button type="button" class="icon-btn icon-btn--accent chat__attach js-only" data-gif-open data-tooltip="GIF y stickers">
                            <?= icon('sticker') ?><span class="sr-only">Enviar un GIF o sticker</span>
                        </button>
                    <?php endif; ?>
                    <button type="button" class="icon-btn icon-btn--accent chat__attach js-only" data-voice-start data-tooltip="Nota de voz">
                        <?= icon('mic') ?><span class="sr-only">Grabar una nota de voz</span>
                    </button>
                    <input class="sr-only" id="chat-image" type="file" name="image" accept="<?= e(implode(',', $imageRules['mimes'])) ?>"
                        data-max-bytes="<?= (int) $imageRules['max_bytes'] ?>" data-chat-image>
                    <label class="sr-only" for="chat-input">Escribe un mensaje</label>
                    <textarea class="chat__input" id="chat-input" name="body" rows="1" maxlength="<?= $maxBody ?>" placeholder="Escribe un mensaje…" data-autosize data-chat-input></textarea>
                    <button type="submit" class="btn btn--primary btn--icon" aria-label="Enviar mensaje"><?= icon('send') ?></button>
                </form>
            <?php endif; ?>

        <?php else: ?>
            <?php View::partial('empty-state', [
                'icon' => 'send', 'heading' => 'Tus mensajes',
                'text' => 'Selecciona una conversación o empieza una nueva. Los mensajes privados solo los ven los participantes.',
                'actionHref' => $viewerId > 0 ? url('messages.php', ['new' => 1]) : null, 'actionLabel' => 'Nuevo mensaje',
            ]); ?>
        <?php endif; ?>
    </section>
</div>
<?php if ($viewerId > 0): ?>
    <script src="<?= e(asset('js/messages.js')) ?>" defer></script>
<?php endif; ?>
