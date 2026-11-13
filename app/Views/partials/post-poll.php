<?php

use Trevix\Core\Auth;

/**
 * Encuesta de una publicación. Sin votar se ven las respuestas como botones (formulario real: funciona sin
 * JavaScript y posts.js lo envía con fetch); después de votar, al terminar o siendo el autor, los porcentajes.
 *
 * @var int   $postId
 * @var array $poll PostPoll::forPosts()
 */
$canVote = Auth::check() && !$poll['show_results'] && !$poll['ended'];
$total = (int) $poll['total'];
?>
<div class="post-poll" data-post-poll="<?= (int) $postId ?>">
    <?php if ($canVote): ?>
        <form method="post" action="<?= e(url('api/posts.php')) ?>" class="post-poll__form" data-poll-form>
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="vote">
            <input type="hidden" name="post_id" value="<?= (int) $postId ?>">
            <?php foreach ($poll['options'] as $option): ?>
                <button type="submit" name="option_id" value="<?= (int) $option['id'] ?>" class="post-poll__option"><?= e($option['label']) ?></button>
            <?php endforeach; ?>
        </form>
    <?php else: ?>
        <ul class="post-poll__results">
            <?php foreach ($poll['options'] as $option): ?>
                <?php $mine = $poll['viewer_vote'] === $option['id']; ?>
                <li class="<?= cx('post-poll__result', ['is-mine' => $mine]) ?>">
                    <span class="post-poll__bar" style="width: <?= (int) ($option['percent'] ?? 0) ?>%"></span>
                    <span class="post-poll__label"><?= e($option['label']) ?><?= $mine ? ' ' . icon('check', '', t('Tu voto')) : '' ?></span>
                    <span class="post-poll__percent"><?= (int) ($option['percent'] ?? 0) ?>%</span>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
    <p class="post-poll__meta">
        <?= e(tn($total, '{n} voto', '{n} votos', ['n' => compact_number($total)])) ?> ·
        <?php if ($poll['ended']): ?>
            <?= e(t('Encuesta terminada')) ?>
        <?php else: ?>
            <?php $left = max(60, (strtotime($poll['ends_at']) ?: time()) - time()); ?>
            <time datetime="<?= e(date(DATE_ATOM, time() + $left)) ?>" title="<?= e(full_date($poll['ends_at'])) ?>"><?= e(match (true) {
                $left < 3600  => t('Quedan {n} min', ['n' => intdiv($left, 60)]),
                $left < 86400 => t('Quedan {n} h', ['n' => intdiv($left, 3600)]),
                default       => tn(intdiv($left, 86400), 'Queda {n} día', 'Quedan {n} días'),
            }) ?></time>
        <?php endif; ?>
    </p>
</div>
