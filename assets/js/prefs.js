/*
 * TREVIX · Preferencias locales aplicadas antes del primer render
 * (se carga de forma síncrona en <head> para evitar parpadeos).
 */
(function () {
    'use strict';

    var root = document.documentElement;
    root.classList.add('js');

    try {
        var prefs = JSON.parse(localStorage.getItem('trevix.prefs') || '{}');
        if (prefs.reduceMotion) {
            root.classList.add('reduce-motion');
        }
        if (prefs.fontSize === 'large' || prefs.fontSize === 'xlarge') {
            root.setAttribute('data-font-size', prefs.fontSize);
        }
        if (localStorage.getItem('trevix.previewBanner') === 'hidden') {
            root.classList.add('preview-banner-hidden');
        }
    } catch (error) {
        /* localStorage no disponible (modo privado estricto): se usan los valores por defecto. */
    }
})();
