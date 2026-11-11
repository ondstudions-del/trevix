<?php

use Trevix\Core\Config;

/*
 * «Abrir en la app» en iPhone, iPad y Android: enlace a la misma pantalla en la app.
 * iOS usa trevix://open/<página>?…; Android, un intent:// con el paquete de la app (si no está instalada,
 * Chrome vuelve a esta página). Oculto por defecto; share.js lo muestra en el teléfono y recuerda si la persona lo cerró.
 */
$ios = (array) Config::get('app.ios', []);
$android = (array) Config::get('app.android', []);
$uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
$page = basename((string) parse_url($uri, PHP_URL_PATH));
$query = (string) parse_url($uri, PHP_URL_QUERY);
$known = in_array($page, (array) ($ios['pages'] ?? []), true);
$scheme = (string) ($ios['scheme'] ?? 'trevix');
$target = 'open/' . ($known ? $page . ($query !== '' ? '?' . $query : '') : '');
$deepLink = $scheme . '://' . $target;
$intent = 'intent://' . $target . '#Intent;scheme=' . $scheme . ';package=' . (string) ($android['package'] ?? 'com.ondsc.trevix')
    . ';S.browser_fallback_url=' . rawurlencode(absolute_url(ltrim((string) parse_url($uri, PHP_URL_PATH), '/') . ($query !== '' ? '?' . $query : ''))) . ';end';
?>
<div class="app-open" data-app-open hidden>
    <span class="app-open__icon"><?php \Trevix\Core\View::partial('logo', ['size' => 28]); ?></span>
    <span class="app-open__text"><strong data-app-open-name><?= e(t('TREVIX para iPhone')) ?></strong><span><?= e($known ? t('Mira esto en la app') : t('Todo es más rápido en la app')) ?></span></span>
    <a class="btn btn--primary btn--sm" href="<?= e($deepLink) ?>" data-app-open-link data-android-href="<?= e($intent) ?>"><?= e(t('Abrir en la app')) ?></a>
    <button type="button" class="icon-btn" data-app-open-close aria-label="<?= e(t('No mostrar más')) ?>"><?= icon('x') ?></button>
</div>
