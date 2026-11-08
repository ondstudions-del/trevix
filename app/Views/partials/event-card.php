<?php

use Trevix\Core\Auth;
use Trevix\Models\Event;

/**
 * Evento dentro de una publicación: portada, fecha, lugar y «Asistiré» / «Me interesa».
 * Los botones son formularios reales (api/events.php); posts.js los envía con fetch y actualiza los contadores.
 *
 * @var array $event Event::cardsFor()
 */
$starts = new DateTimeImmutable((string) $event['starts_at']);
$ends = $event['ends_at'] !== null ? new DateTimeImmutable((string) $event['ends_at']) : null;
$months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
$days = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
$when = $days[(int) $starts->format('w')] . ' ' . $starts->format('j') . ' de ' . $months[(int) $starts->format('n') - 1]
    . ' · ' . $starts->format('H:i')
    . ($ends !== null ? ' – ' . ($ends->format('Y-m-d') === $starts->format('Y-m-d') ? $ends->format('H:i') : $ends->format('j') . ' ' . $months[(int) $ends->format('n') - 1] . ' ' . $ends->format('H:i')) : '');
$response = $event['viewer_response'];
$canRespond = Auth::check() && !$event['is_past'];
$eventId = (int) $event['id'];
?>
<section class="event-card" data-event-card="<?= $eventId ?>" aria-label="Evento: <?= e($event['title']) ?>">
    <?php if (!empty($event['cover_path'])): ?>
        <img class="event-card__cover" src="<?= e(url($event['cover_path'])) ?>" alt="" loading="lazy" decoding="async">
    <?php endif; ?>
    <div class="event-card__body">
        <div class="event-card__date" aria-hidden="true">
            <span><?= e($months[(int) $starts->format('n') - 1]) ?></span>
            <strong><?= e($starts->format('j')) ?></strong>
        </div>
        <div class="event-card__info">
            <p class="event-card__when"><?= icon('clock') ?> <time datetime="<?= e($starts->format(DATE_ATOM)) ?>"><?= e($when) ?></time>
                <?php if ($event['is_past']): ?><span class="chip chip--muted">Finalizado</span><?php endif; ?>
            </p>
            <h3 class="event-card__title"><?= e($event['title']) ?></h3>
            <p class="event-card__place"><?= icon('map-pin') ?> <?= e($event['place']) ?></p>
            <p class="event-card__counts">
                <span data-event-count="going"><?= e(compact_number((int) $event['going_count'])) ?></span> asistirán ·
                <span data-event-count="interested"><?= e(compact_number((int) $event['interested_count'])) ?></span> interesados
            </p>
        </div>
    </div>
    <?php if ($event['description'] !== ''): ?>
        <p class="event-card__description" data-collapsible><?= nl2br(e($event['description'])) ?></p>
    <?php endif; ?>
    <?php if ($canRespond): ?>
        <div class="event-card__actions">
            <?php foreach (Event::RESPONSES as $choice => $label): ?>
                <?php $active = $response === $choice; ?>
                <form method="post" action="<?= e(url('api/events.php')) ?>" data-event-form>
                    <?= csrf_field() ?>
                    <input type="hidden" name="event_id" value="<?= $eventId ?>">
                    <input type="hidden" name="choice" value="<?= $active ? 'none' : e($choice) ?>" data-event-choice="<?= e($choice) ?>">
                    <button type="submit" class="<?= cx('btn', 'btn--sm', $active ? 'btn--primary' : 'btn--secondary') ?>" aria-pressed="<?= $active ? 'true' : 'false' ?>">
                        <?= icon($choice === 'going' ? 'circle-check' : 'star') ?> <?= e($label) ?>
                    </button>
                </form>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</section>
