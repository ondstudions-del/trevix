/*
 * TREVIX · Landing page
 */
(function () {
    'use strict';

    const { $, $$ } = window.Trevix;
    const nav = $('[data-lp-nav]');
    const toggle = $('[data-lp-toggle]');
    const reduceMotion = () => document.documentElement.classList.contains('reduce-motion')
        || window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    /* Navbar con fondo al hacer scroll */
    if (nav) {
        const onScroll = () => nav.classList.toggle('is-scrolled', window.scrollY > 12);
        window.addEventListener('scroll', onScroll, { passive: true });
        onScroll();
    }

    /* Menú móvil */
    if (nav && toggle) {
        const setOpen = (open) => {
            nav.classList.toggle('is-open', open);
            toggle.setAttribute('aria-expanded', String(open));
            toggle.setAttribute('aria-label', open ? 'Cerrar menú' : 'Abrir menú');
        };
        toggle.addEventListener('click', () => setOpen(!nav.classList.contains('is-open')));
        $$('[data-lp-menu] a').forEach((link) => link.addEventListener('click', () => setOpen(false)));
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && nav.classList.contains('is-open')) {
                setOpen(false);
                toggle.focus();
            }
        });
        window.matchMedia('(min-width: 901px)').addEventListener('change', (mq) => {
            if (mq.matches) {
                setOpen(false);
            }
        });
    }

    /* Aparición progresiva de secciones */
    const revealables = $$('[data-reveal]');
    if ('IntersectionObserver' in window && !reduceMotion()) {
        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('is-visible');
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

        revealables.forEach((el) => {
            const siblings = Array.from(el.parentElement.children).filter((child) => child.hasAttribute('data-reveal'));
            el.style.setProperty('--reveal-delay', Math.min(siblings.indexOf(el), 6) * 80 + 'ms');
            observer.observe(el);
        });
    } else {
        revealables.forEach((el) => el.classList.add('is-visible'));
    }

    /* Inclinación sutil del mockup siguiendo el puntero */
    const tilt = $('[data-tilt]');
    const device = tilt ? $('.device', tilt) : null;
    if (tilt && device && window.matchMedia('(hover: hover) and (min-width: 1101px)').matches) {
        tilt.addEventListener('pointermove', (event) => {
            if (reduceMotion()) {
                return;
            }
            const rect = tilt.getBoundingClientRect();
            const x = (event.clientX - rect.left) / rect.width - 0.5;
            const y = (event.clientY - rect.top) / rect.height - 0.5;
            device.style.transform = 'rotateY(' + (-12 + x * 14).toFixed(2) + 'deg) rotateX(' + (6 - y * 10).toFixed(2) + 'deg)';
        });
        tilt.addEventListener('pointerleave', () => {
            device.style.transform = '';
        });
    }
})();
