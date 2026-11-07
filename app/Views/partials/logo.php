<?php
/**
 * Logo oficial de TREVIX: el símbolo # sobre un degradado morado → azul.
 *
 * @var int  $size
 * @var bool $wordmark
 */
$size = $size ?? 36;
$wordmark = $wordmark ?? true;
$gradientId = 'tx-grad-' . bin2hex(random_bytes(4));
?>
<span class="logo">
    <svg class="logo__mark" width="<?= (int) $size ?>" height="<?= (int) $size ?>" viewBox="0 0 64 64" aria-hidden="true" focusable="false">
        <defs>
            <linearGradient id="<?= $gradientId ?>" x1="0" y1="0" x2="64" y2="64" gradientUnits="userSpaceOnUse">
                <stop offset="0" stop-color="#8B5CF6"/>
                <stop offset=".55" stop-color="#7C3AED"/>
                <stop offset="1" stop-color="#2563EB"/>
            </linearGradient>
        </defs>
        <rect width="64" height="64" rx="18" fill="url(#<?= $gradientId ?>)"/>
        <path d="M27.5 14.5 23 49.5M41 14.5 36.5 49.5M16.5 26h32M15.5 38h32" stroke="#fff" stroke-width="5.5" stroke-linecap="round" fill="none"/>
    </svg>
    <?php if ($wordmark): ?>
        <span class="logo__word">TREVIX</span>
    <?php else: ?>
        <span class="sr-only">TREVIX</span>
    <?php endif; ?>
</span>
