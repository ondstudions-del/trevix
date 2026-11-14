<?php
/**
 * Burbuja de un mensaje privado.
 *
 * @var array $message  fila de messages con story, song y gif (Message::withAttachments)
 * @var int   $viewerId
 * @var bool  $isGroup  (opcional) conversación de grupo: muestra quién envía cada mensaje
 * Los mensajes cifrados de extremo a extremo y las fotos de visualización única solo se abren en la app.
 */
$id = (int) $message['id'];
$mine = $message['sender_id'] !== null && (int) $message['sender_id'] === $viewerId;
$deleted = $message['deleted_at'] !== null;
$reply = $message['reply'] ?? null;
$reactions = $message['reactions']['list'] ?? [];
$isGroup = $isGroup ?? false;
$encrypted = !$deleted && ($message['e2ee_epoch'] ?? null) !== null;
$viewOnce = !$deleted && !empty($message['view_once']);
$onceFile = $viewOnce && \Trevix\Services\MediaUpload::isProtected($message['media_path'] ?? null);
if (\Trevix\Services\MediaUpload::isProtected($message['media_path'] ?? null)) {
    $message['media_path'] = null;
}
?>
<?php if (($message['kind'] ?? 'message') === 'system'): ?>
<?php $actor = ($partnerName ?? '') !== '' ? (string) $partnerName : (string) ($message['sender_name'] ?? ''); ?>
<div class="bubble-row bubble-row--system" id="mensaje-<?= $id ?>" data-message-id="<?= $id ?>">
    <p class="bubble-system"><?= icon(str_starts_with((string) $message['body'], 'disappear:') ? 'clock' : (str_starts_with((string) $message['body'], 'group:') ? 'users' : 'lock')) ?>
        <?= e(\Trevix\Models\Conversation::systemText((string) $message['body'], $mine, $actor, $message['target_name'] ?? null, (bool) ($message['target_me'] ?? false), $isGroup)) ?></p>
</div>
<?php return; endif; ?>
<div class="<?= cx('bubble-row', ['bubble-row--mine' => $mine, 'is-deleted' => $deleted]) ?>" id="mensaje-<?= $id ?>" data-message-id="<?= $id ?>"<?= $mine ? ' data-mine' : '' ?>>
    <?php if ($isGroup && !$mine && ($message['sender_name'] ?? '') !== ''): ?>
        <span class="bubble__forwarded"><?= e((string) $message['sender_name']) ?></span>
    <?php endif; ?>
    <?php if ($deleted): ?>
        <p class="bubble bubble--deleted"><?= e(t('Mensaje eliminado')) ?></p>
    <?php elseif ($viewOnce && str_starts_with((string) ($message['media_mime'] ?? ''), 'audio/') && !$encrypted): ?>
        <?php $canListen = !$mine && $viewerId > 0 && empty($message['viewed']) && $onceFile; ?>
        <div class="voice-once<?= $canListen ? '' : ' is-opened' ?>" data-voice-once>
            <?php if ($canListen): ?>
                <button type="button" class="voice-once__play js-only" data-voice-once-play data-url="<?= e(url('api/messages.php', ['action' => 'media', 'id' => $id])) ?>">
                    <?= icon('headphones') ?> <span><?= e(t('Escuchar una vez')) ?></span>
                </button>
                <noscript><span><?= e(t('Nota de voz de una sola vez')) ?></span></noscript>
            <?php else: ?>
                <span><?= icon('eye') ?> <?= e(t('Nota de voz de una sola vez')) ?> · <?= e($mine ? t('Enviada') : t('Escuchada')) ?></span>
            <?php endif; ?>
            <?php if ((int) ($message['media_duration'] ?? 0) > 0): ?>
                <small><?= e(sprintf('%d:%02d', intdiv((int) $message['media_duration'], 60), (int) $message['media_duration'] % 60)) ?></small>
            <?php endif; ?>
        </div>
    <?php elseif ($viewOnce): ?>
        <?php $onceVideo = str_starts_with((string) ($message['media_mime'] ?? ''), 'video/'); ?>
        <p class="bubble bubble--deleted"><?= icon('eye') ?> <?= e($onceVideo ? t('Video de visualización única') : t('Foto de visualización única')) ?> · <?= e($mine ? t('Enviado') : t('Ábrelo en la app TREVIX')) ?></p>
    <?php elseif ($encrypted): ?>
        <p class="bubble bubble--deleted"><?= icon('lock') ?> <?= e(t('Mensaje cifrado de extremo a extremo')) ?> · <?= e(t('Ábrelo en la app TREVIX')) ?></p>
    <?php else: ?>
        <?php if (($message['media_cleared_at'] ?? null) !== null): ?>
            <p class="bubble bubble--deleted"><?= icon('trash-2') ?> <?= e(t('Archivo eliminado para liberar espacio')) ?></p>
        <?php endif; ?>
        <?php if (!empty($message['forwarded'])): ?>
            <span class="bubble__forwarded"><?= icon('share-2') ?> <?= e(t('Reenviado')) ?></span>
        <?php endif; ?>
        <?php if ($reply !== null): ?>
            <a class="bubble__reply" href="#mensaje-<?= (int) $reply['id'] ?>">
                <strong><?= $reply['is_mine'] ? e(t('Tú')) : e((string) $reply['sender_name']) ?></strong>
                <span><?= e(mb_strimwidth((string) $reply['text'], 0, 90, '…')) ?></span>
            </a>
        <?php endif; ?>
        <?php if (($message['location_lat'] ?? null) !== null): ?>
            <?php $coords = rawurlencode($message['location_lat'] . ',' . $message['location_lng']); ?>
            <a class="bubble__location" href="https://www.google.com/maps/search/?api=1&amp;query=<?= e($coords) ?>" target="_blank" rel="noopener">
                <?= icon('map-pin') ?>
                <span><strong><?= e((string) ($message['location_name'] ?: t('Ubicación'))) ?></strong>
                <small><?= e(sprintf('%.5f, %.5f', (float) $message['location_lat'], (float) $message['location_lng'])) ?></small></span>
            </a>
        <?php endif; ?>
        <?php if (!empty($message['story_id'])): ?>
            <?php $story = $message['story'] ?? null; ?>
            <div class="bubble__story">
                <?php $reacted = ($message['context'] ?? null) === 'story_reaction'; ?>
                <span class="bubble__story-label"><?= icon('circle-dashed') ?> <?= e($reacted
                    ? ($mine ? t('Reaccionaste a su historia') : t('Reaccionó a tu historia'))
                    : ($mine ? t('Respondiste a su historia') : t('Respondió a tu historia'))) ?></span>
                <?php if ($story === null): ?>
                    <span class="bubble__story-gone"><?= e(t('La historia ya no está disponible.')) ?></span>
                <?php elseif ($story['media_type'] === 'image'): ?>
                    <img class="bubble__story-thumb" src="<?= e(url($story['media_path'])) ?>" alt="<?= e(t('Historia')) ?>" loading="lazy" decoding="async">
                <?php elseif ($story['media_type'] === 'video'): ?>
                    <video class="bubble__story-thumb" src="<?= e(url($story['media_path'])) ?>#t=0.1" preload="metadata" muted playsinline></video>
                <?php else: ?>
                    <span class="bubble__story-thumb bubble__story-text story-bg--<?= e($story['background'] ?: 'violet') ?>"><?= e(mb_strimwidth((string) $story['body'], 0, 60, '…')) ?></span>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        <?php if (!empty($message['shared_post'])): ?>
            <?php $shared = $message['shared_post']; ?>
            <?php if (empty($shared['available'])): ?>
                <div class="bubble__shared bubble__shared--gone"><?= icon('eye-off') ?> <?= e(t('Esta publicación ya no está disponible.')) ?></div>
            <?php else: ?>
                <a class="bubble__shared" href="<?= e(url('post.php', ['id' => (int) $shared['id']])) ?>">
                    <span class="bubble__shared-head">
                        <?= avatar($shared['user'], 'xs') ?>
                        <strong><?= e((string) $shared['user']['display_name']) ?></strong>
                        <?php if ($shared['is_reel']): ?><span class="bubble__shared-tag"><?= icon('clapperboard') ?> <?= e(t('Reel')) ?></span><?php endif; ?>
                    </span>
                    <?php if (!empty($shared['thumb']) && empty($shared['is_adult'])): ?>
                        <span class="bubble__shared-media<?= $shared['is_reel'] ? ' bubble__shared-media--reel' : '' ?>">
                            <img src="<?= e(url($shared['thumb'])) ?>" alt="" loading="lazy" decoding="async">
                            <?php if ($shared['is_reel']): ?><span class="bubble__shared-play"><?= icon('play') ?></span><?php endif; ?>
                        </span>
                    <?php elseif ($shared['body'] !== '' && $shared['format'] === 'thread' && $shared['background']): ?>
                        <span class="bubble__shared-media bubble__shared-text story-bg--<?= e((string) $shared['background']) ?>"><?= e($shared['body']) ?></span>
                    <?php endif; ?>
                    <?php if ($shared['body'] !== '' && !($shared['format'] === 'thread' && $shared['background'])): ?>
                        <span class="bubble__shared-body"><?= e($shared['body']) ?></span>
                    <?php endif; ?>
                </a>
            <?php endif; ?>
        <?php endif; ?>
        <?php if (($message['context'] ?? null) === 'note_reply' && ($message['note_text'] ?? null) !== null): ?>
            <div class="bubble__reply bubble__note">
                <strong><?= e($mine ? t('Respondiste a su nota') : t('Respondió a tu nota')) ?></strong>
                <span><?= e((string) $message['note_text']) ?></span>
            </div>
        <?php endif; ?>
        <?php if (!empty($message['media_path']) && str_starts_with((string) $message['media_mime'], 'audio/')): ?>
            <?php $seconds = (int) ($message['media_duration'] ?? 0); ?>
            <div class="voice-note" data-song-player>
                <button type="button" class="voice-note__play js-only" data-song-toggle aria-label="<?= e(t('Reproducir nota de voz')) ?>">
                    <span class="song-chip__icon-play"><?= icon('play') ?></span>
                    <span class="song-chip__icon-pause"><?= icon('pause') ?></span>
                </button>
                <span class="voice-note__wave" aria-hidden="true"><?= icon('audio-lines') ?><span class="song-chip__bar"><span data-song-progress></span></span></span>
                <span class="voice-note__time" data-song-time><?= e(sprintf('%d:%02d', intdiv($seconds, 60), $seconds % 60)) ?></span>
                <audio preload="none" src="<?= e(url($message['media_path'])) ?>" data-start="0" data-end="0">
                    <a href="<?= e(url($message['media_path'])) ?>"><?= e(t('Escuchar la nota de voz')) ?></a>
                </audio>
            </div>
        <?php elseif (!empty($message['media_path']) && str_starts_with((string) $message['media_mime'], 'video/')): ?>
            <div class="bubble__media bubble__media--video">
                <video controls playsinline preload="metadata" src="<?= e(url($message['media_path'])) ?>"<?= !empty($message['media_poster']) ? ' poster="' . e(url($message['media_poster'])) . '"' : '' ?>
                    <?= !empty($message['media_width']) && !empty($message['media_height']) ? 'width="' . (int) $message['media_width'] . '" height="' . (int) $message['media_height'] . '"' : '' ?>></video>
            </div>
        <?php elseif (!empty($message['media_path'])): ?>
            <a class="bubble__media" href="<?= e(url($message['media_path'])) ?>" target="_blank" rel="noopener">
                <img src="<?= e(url($message['media_path'])) ?>" alt="<?= e(t('Imagen enviada')) ?>" loading="lazy" decoding="async">
            </a>
        <?php endif; ?>
        <?php if (!empty($message['gif'])): ?>
            <div class="bubble__gif"><?php \Trevix\Core\View::partial('gif', ['gif' => $message['gif']]); ?></div>
        <?php endif; ?>
        <?php if (!empty($message['gift'])): ?>
            <?php $gift = $message['gift']; ?>
            <div class="message__gift">
                <span class="message__gift-label"><?= icon('gift') ?> <?= e($mine ? t('Enviaste un regalo') : t('Te envió un regalo')) ?></span>
                <img src="<?= e((string) $gift['media_url']) ?>" alt="<?= e((string) $gift['name']) ?>" loading="lazy" decoding="async"<?= $gift['width'] > 0 && $gift['height'] > 0 ? ' width="' . (int) $gift['width'] . '" height="' . (int) $gift['height'] . '"' : '' ?>>
                <strong><?= e((string) $gift['name']) ?></strong>
            </div>
        <?php endif; ?>
        <?php if (!empty($message['song'])): ?>
            <div class="bubble__song"><?php \Trevix\Core\View::partial('song-chip', ['song' => $message['song'], 'mode' => 'full']); ?></div>
        <?php endif; ?>
        <?php if ((string) $message['body'] !== '' && empty($message['gift'])): ?>
            <p class="bubble"><?= format_post_body((string) $message['body'], false) ?></p>
        <?php endif; ?>
    <?php endif; ?>
    <?php if (!$deleted && $reactions !== []): ?>
        <?php $myReaction = $message['reactions']['mine'] ?? null; ?>
        <span class="bubble__reactions"><?php foreach ($reactions as $r): ?><span<?= $myReaction === $r['emoji'] ? ' class="is-mine"' : '' ?>><?= e((string) $r['emoji']) ?><?= $r['count'] > 1 ? ' ' . (int) $r['count'] : '' ?></span><?php endforeach; ?></span>
    <?php endif; ?>
    <span class="bubble__meta">
        <?php if (!$deleted && ($message['pinned_at'] ?? null) !== null): ?><span class="bubble__flag" title="<?= e(t('Fijado')) ?>"><?= icon('pin') ?></span><?php endif; ?>
        <?php if (!$deleted && ($message['expires_at'] ?? null) !== null): ?><span class="bubble__flag" title="<?= e(t('Mensaje temporal')) ?>"><?= icon('clock') ?></span><?php endif; ?>
        <?= time_tag((string) $message['created_at']) ?>
        <?php if (!$deleted && $viewerId > 0): ?>
            <button type="button" class="bubble__delete js-only" data-react-open data-my-reaction="<?= e((string) ($message['reactions']['mine'] ?? '')) ?>"
                aria-label="<?= e(t('Reaccionar')) ?>" data-tooltip="<?= e(t('Reaccionar')) ?>"><?= icon('smile') ?></button>
        <?php endif; ?>
        <?php if ($mine && !$deleted && $viewerId > 0): ?>
            <form class="bubble__delete-form" method="post" action="<?= e(url('api/messages.php')) ?>" data-message-delete>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="message_id" value="<?= $id ?>">
                <button type="submit" class="bubble__delete" aria-label="<?= e(t('Eliminar mensaje')) ?>" data-tooltip="<?= e(t('Eliminar')) ?>"><?= icon('trash-2') ?></button>
            </form>
        <?php elseif (!$mine && !$deleted && $viewerId > 0 && $message['sender_id'] !== null): ?>
            <a class="bubble__delete" href="<?= e(url('report.php', ['type' => 'message', 'id' => $id])) ?>"
                data-report="message" data-report-id="<?= $id ?>" data-report-label="<?= e(t('este mensaje')) ?>"
                aria-label="<?= e(t('Reportar mensaje')) ?>" data-tooltip="<?= e(t('Reportar')) ?>"><?= icon('flag') ?></a>
        <?php endif; ?>
    </span>
</div>
