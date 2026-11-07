<?php
/**
 * Burbuja de un mensaje privado.
 *
 * @var array $message  fila de messages con story y song (Message::withAttachments)
 * @var int   $viewerId
 */
$id = (int) $message['id'];
$mine = $message['sender_id'] !== null && (int) $message['sender_id'] === $viewerId;
$deleted = $message['deleted_at'] !== null;
?>
<div class="<?= cx('bubble-row', ['bubble-row--mine' => $mine, 'is-deleted' => $deleted]) ?>" id="mensaje-<?= $id ?>" data-message-id="<?= $id ?>"<?= $mine ? ' data-mine' : '' ?>>
    <?php if ($deleted): ?>
        <p class="bubble bubble--deleted">Mensaje eliminado</p>
    <?php else: ?>
        <?php if (!empty($message['story_id'])): ?>
            <?php $story = $message['story'] ?? null; ?>
            <div class="bubble__story">
                <span class="bubble__story-label"><?= icon('circle-dashed') ?> <?= $mine ? 'Respondiste a su historia' : 'Respondió a tu historia' ?></span>
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
        <?php if (!empty($message['media_path'])): ?>
            <a class="bubble__media" href="<?= e(url($message['media_path'])) ?>" target="_blank" rel="noopener">
                <img src="<?= e(url($message['media_path'])) ?>" alt="Imagen enviada" loading="lazy" decoding="async">
            </a>
        <?php endif; ?>
        <?php if (!empty($message['song'])): ?>
            <div class="bubble__song"><?php \Trevix\Core\View::partial('song-chip', ['song' => $message['song'], 'mode' => 'full']); ?></div>
        <?php endif; ?>
        <?php if ((string) $message['body'] !== ''): ?>
            <p class="bubble"><?= format_post_body((string) $message['body']) ?></p>
        <?php endif; ?>
    <?php endif; ?>
    <span class="bubble__meta">
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
