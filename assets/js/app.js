/*
 * TREVIX · Comportamiento del shell de la aplicación
 */
(function () {
    'use strict';

    const { $, $$, prefs } = window.Trevix;

    /* ---------- Barra de historias: flechas de desplazamiento ---------- */
    $$('[data-stories]').forEach((bar) => {
        const track = $('[data-stories-track]', bar);
        const prev = $('[data-stories-prev]', bar);
        const next = $('[data-stories-next]', bar);
        if (!track || !prev || !next) {
            return;
        }
        const update = () => {
            prev.hidden = track.scrollLeft < 8;
            next.hidden = track.scrollLeft + track.clientWidth >= track.scrollWidth - 8;
        };
        prev.addEventListener('click', () => track.scrollBy({ left: -track.clientWidth * 0.8 }));
        next.addEventListener('click', () => track.scrollBy({ left: track.clientWidth * 0.8 }));
        track.addEventListener('scroll', update, { passive: true });
        window.addEventListener('resize', update);
        update();
    });

    /* ---------- Textos largos: "Ver más" (también para tarjetas cargadas después) ---------- */
    function initCollapsible(root = document) {
        const bodies = root.matches && root.matches('[data-collapsible]') ? [root] : $$('[data-collapsible]', root);
        bodies.forEach(setupCollapsible);
    }

    function setupCollapsible(body) {
        if (body.dataset.collapsibleReady) {
            return;
        }
        body.dataset.collapsibleReady = '1';
        body.classList.add('is-collapsed');
        if (body.scrollHeight <= body.clientHeight + 4) {
            body.classList.remove('is-collapsed');
            return;
        }
        const toggle = document.createElement('button');
        toggle.type = 'button';
        toggle.className = 'post__expand';
        toggle.textContent = 'Ver más';
        toggle.setAttribute('aria-expanded', 'false');
        toggle.addEventListener('click', () => {
            const collapsed = body.classList.toggle('is-collapsed');
            toggle.textContent = collapsed ? 'Ver más' : 'Ver menos';
            toggle.setAttribute('aria-expanded', String(!collapsed));
        });
        body.after(toggle);
    }

    initCollapsible();
    window.Trevix.initCollapsible = initCollapsible;

    /* ---------- Visor de imágenes ---------- */
    const lightbox = $('#lightbox');
    if (lightbox) {
        const img = $('[data-lightbox-img]', lightbox);
        const caption = $('[data-lightbox-caption]', lightbox);
        const prevBtn = $('[data-lightbox-prev]', lightbox);
        const nextBtn = $('[data-lightbox-next]', lightbox);
        let images = [];
        let index = 0;

        const render = () => {
            const current = images[index];
            img.src = current.currentSrc || current.src;
            img.alt = current.alt;
            caption.textContent = current.alt;
            prevBtn.hidden = nextBtn.hidden = images.length < 2;
        };

        const step = (delta) => {
            index = (index + delta + images.length) % images.length;
            render();
        };

        document.addEventListener('click', (event) => {
            const opener = event.target.closest('[data-lightbox-index]');
            if (!opener) {
                return;
            }
            const group = opener.closest('[data-lightbox-group]');
            images = $$('[data-lightbox-index] img', group);
            index = Number(opener.getAttribute('data-lightbox-index')) || 0;
            render();
            lightbox.showModal();
        });

        prevBtn.addEventListener('click', () => step(-1));
        nextBtn.addEventListener('click', () => step(1));
        lightbox.addEventListener('keydown', (event) => {
            if (event.key === 'ArrowLeft') {
                step(-1);
            } else if (event.key === 'ArrowRight') {
                step(1);
            }
        });
    }

    /* ---------- Header móvil: se oculta al bajar y reaparece al subir ---------- */
    const header = $('.mobile-header');
    const mobile = window.matchMedia('(max-width: 767px)');
    if (header) {
        let lastY = window.scrollY;
        let ticking = false;
        const onScroll = () => {
            const y = window.scrollY;
            const hide = mobile.matches && y > 120 && y > lastY + 4;
            const show = y < lastY - 4 || y < 120;
            if (hide) {
                header.classList.add('is-hidden');
                document.documentElement.classList.add('is-header-hidden');
            } else if (show) {
                header.classList.remove('is-hidden');
                document.documentElement.classList.remove('is-header-hidden');
            }
            lastY = y;
            ticking = false;
        };
        window.addEventListener('scroll', () => {
            if (!ticking) {
                ticking = true;
                window.requestAnimationFrame(onScroll);
            }
        }, { passive: true });
    }

    /* ---------- Conversaciones: mostrar el último mensaje ---------- */
    $$('[data-chat-scroll]').forEach((el) => {
        el.scrollTop = el.scrollHeight;
    });

    /* ---------- Preferencias de apariencia (guardadas en este dispositivo) ---------- */
    $$('[data-pref]').forEach((input) => {
        const key = input.getAttribute('data-pref');
        const stored = prefs.get(key);
        if (input.type === 'checkbox') {
            input.checked = Boolean(stored);
        } else if (input.type === 'radio') {
            input.checked = (stored || 'normal') === input.value;
        }
        input.addEventListener('change', () => {
            if (input.type === 'checkbox') {
                prefs.set(key, input.checked);
            } else if (input.checked) {
                prefs.set(key, input.value);
            }
            window.Trevix.toast('Preferencia guardada en este dispositivo', 'success', 2200);
        });
    });
})();
