/*
 * TREVIX · Tiempo en pantalla
 * Mide cuánto tiempo está visible (al menos la mitad) cada publicación y, al dejar de verse, lo envía a
 * api/signals.php: lo que se mira mucho rato alimenta los intereses de «Para ti».
 */
(function () {
    'use strict';

    const { config } = window.Trevix;
    if (!('IntersectionObserver' in window) || !('MutationObserver' in window) || !navigator.sendBeacon || !config.csrfToken) {
        return;
    }
    const MIN_SECONDS = 3;
    const SELECTOR = 'article.post[data-post-id]';
    const visibleSince = new Map();
    const total = new Map();
    const sent = new Map();

    function send(id) {
        const seconds = Math.floor(total.get(id) || 0);
        if (seconds < MIN_SECONDS || seconds <= (sent.get(id) || 0)) {
            return;
        }
        sent.set(id, seconds);
        const data = new FormData();
        data.append('_csrf', config.csrfToken);
        data.append('post_id', id);
        data.append('kind', 'view');
        data.append('seconds', String(seconds));
        navigator.sendBeacon((config.baseUrl || '') + '/api/signals.php', data);
    }

    function stop(el) {
        const since = visibleSince.get(el);
        if (since === undefined) {
            return;
        }
        visibleSince.delete(el);
        const id = el.getAttribute('data-post-id');
        total.set(id, (total.get(id) || 0) + (performance.now() - since) / 1000);
        send(id);
    }

    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting && !document.hidden) {
                if (!visibleSince.has(entry.target)) {
                    visibleSince.set(entry.target, performance.now());
                }
            } else {
                stop(entry.target);
            }
        });
    }, { threshold: 0.5 });

    function watch(root) {
        const items = root.matches && root.matches(SELECTOR) ? [root] : Array.from(root.querySelectorAll(SELECTOR));
        items.forEach((el) => {
            if (!el.hasAttribute('data-watched')) {
                el.setAttribute('data-watched', '');
                observer.observe(el);
            }
        });
    }

    function stopAll() {
        Array.from(visibleSince.keys()).forEach(stop);
    }

    watch(document);
    new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
            mutation.addedNodes.forEach((node) => {
                if (node.nodeType === 1) {
                    watch(node);
                }
            });
            mutation.removedNodes.forEach((node) => {
                if (node.nodeType === 1 && visibleSince.has(node)) {
                    stop(node);
                }
            });
        });
    }).observe(document.body, { childList: true, subtree: true });

    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            stopAll();
            return;
        }
        // Al volver a la pestaña, el observador vuelve a informar qué publicaciones siguen en pantalla.
        document.querySelectorAll(SELECTOR + '[data-watched]').forEach((el) => {
            observer.unobserve(el);
            observer.observe(el);
        });
    });
    window.addEventListener('pagehide', stopAll);
})();
