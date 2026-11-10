<?php
/**
 * Burbuja de un mensaje privado.
 *
 * @var array $message  fila de messages con story, song y gif (Message::withAttachments)
 * @var int   $viewerId
 */
$id = (int) $message['id'];
$mine = $message['sender_id'] !== null && (int) $message['sender_id'] === $viewerId;
$deleted = $message['deleted_at'] !== null;
$reply = $message['reply'] ?? null;
$reactions = $message['reactions']['list'] ?? [];
?>
<?php if (($message['kind'] ?? 'message') === 'system'): ?>
<div class="bubble-row bubble-row--system" id="mensaje-<?= $id ?>" data-message-id="<?= $id ?>">
    <p class="bubble-system"><?= icon('clock') ?> <?= e(\Trevix\Models\Conversation::systemText((string) $message['body'], $mine, (string) ($partnerName ?? ''))) ?></p>
</div>
<?php return; endif; ?>
<div class="<?= cx('bubble-row', ['bubble-row--mine' => $mine, 'is-deleted' => $deleted]) ?>" id="mensaje-<?= $id ?>" data-message-id="<?= $id ?>"<?= $mine ? ' data-mine' : '' ?>>
    <?php if ($deleted): ?>
        <p class="bubble bubble--deleted">Mensaje eliminado</p>
    <?php else: ?>
        <?php if (!empty($message['forwarded'])): ?>
            <span class="bubble__forwarded"><?= icon('share-2') ?> Reenviado</span>
        <?php endif; ?>
        <?php if ($reply !== null): ?>
            <a class="bubble__reply" href="#mensaje-<?= (int) $reply['id'] ?>">
                <strong><?= $reply['is_mine'] ? 'Tú' : e((string) $reply['sender_name']) ?></strong>
                <span><?= e(mb_strimwidth((string) $reply['text'], 0, 90, '…')) ?></span>
            </a>
        <?php endif; ?>
        <?php if (($message['location_lat'] ?? null) !== null): ?>
            <?php $coords = rawurlencode($message['location_lat'] . ',' . $message['location_lng']); ?>
            <a class="bubble__location" href="https://www.google.com/maps/search/?api=1&amp;query=<?= e($coords) ?>" target="_blank" rel="noopener">
                <?= icon('map-pin') ?>
                <span><strong><?= e((string) ($message['location_name'] ?: 'Ubicación')) ?></strong>
                <small><?= e(sprintf('%.5f, %.5f', (float) $message['location_lat'], (float) $message['location_lng'])) ?></small></span>
            </a>
        <?php endif; ?>
        <?php if (!empty($message['story_id'])): ?>
            <?php $story = $message['story'] ?? null; ?>
            <div class="bubble__story">
                <?php $reacted = ($message['context'] ?? null) === 'story_reaction'; ?>
                <span class="bubble__story-label"><?= icon('circle-dashed') ?> <?= $reacted
                    ? ($mine ? 'Reaccionaste a su historia' : 'Reaccionó a tu historia')
                    : ($mine ? 'Respondiste a su historia' : 'Respondió a tu historia') ?></span>
                <?php if ($story === null): ?>
                    <span class="bubble__story-gone">La historia ya no está disponible.</span>
                <?php elseif ($story['media_type'] === 'image'): ?>
                    <img class="bubble__story-thumb" src="<?= e(url($story['media_path'])) ?>" alt="Historia" loading="lazy" decoding="async">
                <?php elseif ($story['media_type'] === 'video'): ?>
                    <video class="bubble__story-thumb" src="<?= e(url($story['media_path'])) ?>#t=0.1" preload="metadata" muted playsinline></video>
                <?php else: ?>
                    <span class="bubble__story-thumb bubble__story-text story-bg--<?= e($story['background'] ?: 'violet') ?>"><?= e(mb_strimwidth((string) $story['body'], 0, 60, '…')) ?></span>
                <?php endif; ?>
            </div>
        <?php endif; ?>
        <?php if (($message['context'] ?? null) === 'note_reply' && ($message['note_text'] ?? null) !== null): ?>
            <div class="bubble__reply bubble__note">
                <strong><?= $mine ? 'Respondiste a su nota' : 'Respondió a tu nota' ?></strong>
                <span><?= e((string) $message['note_text']) ?></span>
            </div>
        <?php endif; ?>
        <?php if (!empty($message['media_path']) && str_starts_with((string) $message['media_mime'], 'audio/')): ?>
            <?php $seconds = (int) ($message['media_duration'] ?? 0); ?>
            <div class="voice-note" data-song-player>
                <button type="button" class="voice-note__play js-only" data-song-toggle aria-label="Reproducir nota de voz">
                    <span class="song-chip__icon-play"><?= icon('play') ?></span>
                    <span class="song-chip__icon-pause"><?= icon('pause') ?></span>
                </button>
                <span class="voice-note__wave" aria-hidden="true"><?= icon('audio-lines') ?><span class="song-chip__bar"><span data-song-progress></span></span></span>
                <span class="voice-note__time" data-song-time><?= e(sprintf('%d:%02d', intdiv($seconds, 60), $seconds % 60)) ?></span>
                <audio preload="none" src="<?= e(url($message['media_path'])) ?>" data-start="0" data-end="0">
                    <a href="<?= e(url($message['media_path'])) ?>">Escuchar la nota de voz</a>
                </audio>
            </div>
        <?php elseif (!empty($message['media_path'])): ?>
            <a class="bubble__media" href="<?= e(url($message['media_path'])) ?>" target="_blank" rel="noopener">
                <img src="<?= e(url($message['media_path'])) ?>" alt="Imagen enviada" loading="lazy" decoding="async">
            </a>
        <?php endif; ?>
        <?php if (!empty($message['gif'])): ?>
            <div class="bubble__gif"><?php \Trevix\Core\View::partial('gif', ['gif' => $message['gif']]); ?></div>
        <?php endif; ?>
        <?php if (!empty($message['song'])): ?>
            <div class="bubble__song"><?php \Trevix\Core\View::partial('song-chip', ['song' => $message['song'], 'mode' => 'full']); ?></div>
        <?php endif; ?>
        <?php if ((string) $message['body'] !== ''): ?>
            <p class="bubble"><?= format_post_body((string) $message['body']) ?></p>
        <?php endif; ?>
        <?php if ($reactions !== []): ?>
            <span class="bubble__reactions"><?php foreach ($reactions as $r): ?><span><?= e((string) $r['emoji']) ?><?= $r['count'] > 1 ? ' ' . (int) $r['count'] : '' ?></span><?php endforeach; ?></span>
        <?php endif; ?>
    <?php endif; ?>
    <span class="bubble__meta">
        <?php if (!$deleted && ($message['pinned_at'] ?? null) !== null): ?><span class="bubble__flag" title="Fijado"><?= icon('pin') ?></span><?php endif; ?>
        <?php if (!$deleted && ($message['expires_at'] ?? null) !== null): ?><span class="bubble__flag" title="Mensaje temporal"><?= icon('clock') ?></span><?php endif; ?>
        <?= time_tag((string) $message['created_at']) ?>
        <?php if ($mine && !$deleted && $viewerId > 0): ?>
            <form class="bubble__delete-form" method="post" action="<?= e(url('api/messages.php')) ?>" data-message-delete>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="message_id" value="<?= $id ?>">
                <button type="submit" class="bubble__delete" aria-label="Eliminar mensaje" data-tooltip="Eliminar"><?= icon('trash-2') ?></button>
            </form>
        <?php elseif (!$mine && !$deleted && $viewerId > 0 && $message['sender_id'] !== null): ?>
            <a class="bubble__delete" href="<?= e(url('report.php', ['type' => 'message', 'id' => $id])) ?>"
                data-report="message" data-report-id="<?= $id ?>" data-report-label="este mensaje"
                aria-label="Reportar mensaje" data-tooltip="Reportar"><?= icon('flag') ?></a>
        <?php endif; ?>
    </span>
</div>
