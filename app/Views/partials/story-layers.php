<?php
/**
 * Capas de una historia con foto o video (textos, stickers, ubicación, encuesta, menciones y enlace).
 * Las medidas son proporcionales al ancho de la historia (unidades cqw) para que se vean igual que en la app.
 *
 * @var array $item  elemento de Story::groupsFor (overlays, poll)
 * @var bool  $own   si la historia es de quien mira
 */
$layers = $item['overlays'] ?? [];
if ($layers === []) {
    return;
}
$poll = $item['poll'] ?? null;
?>
<div class="story-layers">
    <?php foreach ($layers as $layer): ?>
        <?php
        $style = sprintf(
            'left:%.2f%%;top:%.2f%%;--layer-scale:%.3f;--layer-rotate:%.4frad',
            (float) $layer['x'] * 100, (float) $layer['y'] * 100, (float) $layer['scale'], (float) $layer['rotation']
        );
        ?>
        <?php switch ($layer['type']):
            case 'text': ?>
                <p class="story-layer story-layer--text story-layer--<?= e($layer['style']) ?>" style="<?= e($style) ?>;--layer-color:<?= e($layer['color']) ?>"><?= nl2br(e($layer['text']), false) ?></p>
                <?php break; ?>
            <?php case 'sticker': ?>
                <img class="story-layer story-layer--sticker" style="<?= e($style) ?>" src="<?= e($layer['url']) ?>" alt="" loading="lazy" decoding="async"
                    width="<?= (int) $layer['width'] ?>" height="<?= (int) $layer['height'] ?>">
                <?php break; ?>
            <?php case 'location': ?>
                <a class="story-layer story-layer--chip" style="<?= e($style) ?>" target="_blank" rel="noopener"
                    href="<?= e('https://www.openstreetmap.org/search?query=' . rawurlencode($layer['name'])) ?>"><?= icon('map-pin') ?> <?= e($layer['name']) ?></a>
                <?php break; ?>
            <?php case 'mention': ?>
                <a class="story-layer story-layer--chip" style="<?= e($style) ?>" href="<?= e(url('profile.php', ['u' => $layer['username']])) ?>">@<?= e($layer['username']) ?></a>
                <?php break; ?>
            <?php case 'link': ?>
                <a class="story-layer story-layer--chip story-layer--link" style="<?= e($style) ?>" href="<?= e($layer['url']) ?>" target="_blank" rel="noopener nofollow ugc"><?= icon('link') ?> <?= e($layer['label']) ?></a>
                <?php break; ?>
            <?php case 'poll': ?>
                <?php
                $voted = $poll !== null && $poll['viewer_choice'] !== null;
                $counts = $poll['counts'] ?? null;
                $total = max(1, (int) ($poll['total'] ?? 0));
                ?>
                <form class="story-layer story-layer--poll<?= $counts !== null ? ' has-results' : '' ?>" style="<?= e($style) ?>" method="post"
                    action="<?= e(url('api/stories.php')) ?>" data-story-poll>
                    <?= csrf_field() ?>
                    <input type="hidden" name="action" value="poll">
                    <input type="hidden" name="story_id" value="<?= (int) $item['id'] ?>">
                    <p class="story-poll__question"><?= e($layer['question']) ?></p>
                    <?php foreach ($layer['options'] as $index => $option): ?>
                        <?php $percent = $counts !== null ? (int) round($counts[$index] * 100 / $total) : 0; ?>
                        <button type="submit" name="choice" value="<?= $index ?>" class="<?= cx('story-poll__option', ['is-chosen' => $voted && (int) $poll['viewer_choice'] === $index]) ?>"
                            <?= $voted || !empty($own) ? 'disabled' : '' ?> style="--poll-percent:<?= $percent ?>%">
                            <span class="story-poll__label"><?= e($option) ?></span>
                            <span class="story-poll__percent" data-poll-percent><?= $counts !== null ? $percent . '%' : '' ?></span>
                        </button>
                    <?php endforeach; ?>
                    <?php if (!empty($own)): ?>
                        <p class="story-poll__total"><?= e(tn((int) ($poll['total'] ?? 0), '{n} voto', '{n} votos')) ?></p>
                    <?php endif; ?>
                </form>
                <?php break; ?>
        <?php endswitch; ?>
    <?php endforeach; ?>
</div>
