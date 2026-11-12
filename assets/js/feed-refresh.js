/*
 * TREVIX · Publicaciones nuevas en el inicio
 * Cada 30 s (con la pestaña visible) pregunta cuántas publicaciones nuevas hay arriba y muestra el aviso
 * «N publicaciones nuevas». Tocar el aviso, o deslizar hacia abajo estando arriba del todo (pantallas táctiles),
 * vuelve a cargar la primera página del feed sin recargar la página.
 */
(function () {
    'use strict';

    const { $, $$, t } = window.Trevix;
    const feed = $('[data-feed-refresh]');
    if (!feed) {
        return;
    }
    const baseUrl = feed.getAttribute('data-feed-refresh');
    const counts = !feed.hasAttribute('data-feed-no-count');
    const pill = $('[data-feed-new]');
    const pillLabel = $('[data-feed-new-label]');
    const pull = $('[data-feed-pull]');
    const INTERVAL = 30000;
    const PULL_TRIGGER = 80;
    let timer = null;
    let loading = false;

    function newestId() {
        return $$('[data-post-id]', feed).reduce((max, el) => Math.max(max, Number(el.getAttribute('data-post-id')) || 0), 0);
    }

    function showPill(count) {
        if (!pill) {
            return;
        }
        pill.hidden = count < 1;
        if (count > 0) {
            pillLabel.textContent = count === 1
                ? t('1 publicación nueva')
                : t('{n} publicaciones nuevas', { n: count > 98 ? '99+' : count });
        }
    }

    async function check() {
        if (!counts || document.hidden || loading) {
            return;
        }
        const newest = newestId();
        if (newest < 1) {
            return;
        }
        try {
            const url = new URL(baseUrl, window.location.href);
            url.searchParams.set('newer', String(newest));
            const response = await fetch(url, { headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' });
            const payload = await response.json();
            if (payload && payload.ok) {
                showPill(Number(payload.count) || 0);
            }
        } catch {
            // Sin conexión: se vuelve a intentar en el próximo ciclo.
        }
    }

    async function refresh() {
        if (loading) {
            return;
        }
        loading = true;
        feed.setAttribute('aria-busy', 'true');
        pull?.classList.add('is-loading');
        try {
            const url = new URL(baseUrl, window.location.href);
            url.searchParams.set('partial', '1');
            const response = await fetch(url, { headers: { 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' });
            if (!response.ok) {
                throw new Error();
            }
            const html = (await response.text()).trim();
            if (html !== '') {
                feed.innerHTML = html;
                if (window.Trevix.enhancePosts) {
                    window.Trevix.enhancePosts(feed);
                }
            }
            showPill(0);
            window.scrollTo({ top: 0, behavior: 'smooth' });
        } catch {
            window.Trevix.toast(t('No se pudo actualizar el feed. Inténtalo de nuevo.'), 'error');
        } finally {
            loading = false;
            feed.removeAttribute('aria-busy');
            pull?.classList.remove('is-loading');
            if (pull) {
                pull.style.removeProperty('--pull');
            }
        }
    }

    function schedule() {
        clearInterval(timer);
        timer = setInterval(check, INTERVAL);
    }

    pill?.addEventListener('click', refresh);
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden) {
            check();
        }
    });

    // Deslizar hacia abajo estando arriba del todo.
    let startY = null;
    let distance = 0;
    window.addEventListener('touchstart', (event) => {
        startY = window.scrollY <= 0 && event.touches.length === 1 ? event.touches[0].clientY : null;
        distance = 0;
    }, { passive: true });
    window.addEventListener('touchmove', (event) => {
        if (startY === null || loading) {
            return;
        }
        distance = Math.max(0, event.touches[0].clientY - startY);
        if (pull) {
            pull.style.setProperty('--pull', String(Math.min(distance, PULL_TRIGGER * 1.5)));
            pull.classList.toggle('is-ready', distance >= PULL_TRIGGER);
        }
    }, { passive: true });
    window.addEventListener('touchend', () => {
        if (startY !== null && distance >= PULL_TRIGGER) {
            refresh();
        } else if (pull && !loading) {
            pull.style.removeProperty('--pull');
        }
        pull?.classList.remove('is-ready');
        startY = null;
        distance = 0;
    });

    schedule();
})();
