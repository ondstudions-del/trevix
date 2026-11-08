<?php

use Trevix\Core\Config;

/*
 * «Abrir en la app» en iPhone y iPad: enlace trevix://open/<página>?… a la misma pantalla en la app.
 * Oculto por defecto; share.js lo muestra solo en iOS y recuerda si la persona lo cerró.
 */
$ios = (array) Config::get('app.ios', []);
$page = basename((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH));
$query = (string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_QUERY);
$known = in_array($page, (array) ($ios['pages'] ?? []), true);
$deepLink = ($ios['scheme'] ?? 'trevix') . '://open/' . ($known ? $page . ($query !== '' ? '?' . $query : '') : '');
?>
<div class="app-open" data-app-open hidden>
    <span class="app-open__icon"><?php \Trevix\Core\View::partial('logo', ['size' => 28]); ?></span>
    <span class="app-open__text"><strong>TREVIX para iPhone</strong><span><?= $known ? 'Mira esto en la app' : 'Todo es más rápido en la app' ?></span></span>
    <a class="btn btn--primary btn--sm" href="<?= e($deepLink) ?>" data-app-open-link>Abrir en la app</a>
    <button type="button" class="icon-btn" data-app-open-close aria-label="No mostrar más"><?= icon('x') ?></button>
</div>
