/*
 * TREVIX · Interacciones con publicaciones
 * Me gusta y guardar (formularios reales enviados con fetch), confirmación de acciones destructivas
 * y paginación del feed ("Cargar más" + carga automática al llegar al final).
 * Sin JavaScript, los mismos formularios y enlaces funcionan con recarga de página.
 */
(function () {
    'use strict';

    const { $, $$, toast, config, t } = window.Trevix;

    /** Misma lógica que compact_number() en PHP. */
    function compactNumber(n) {
        if (n < 1000) {
            return String(n);
        }
        const en = config.lang === 'en';
        const [value, suffix] = n < 1000000 ? [n / 1000, en ? 'K' : ' mil'] : [n / 1000000, en ? 'M' : ' M'];
        const formatted = (Math.floor(value * 10) / 10).toFixed(1);
        return (en ? formatted.replace(/\.0$/, '') : formatted.replace('.', ',').replace(/,0$/, '')) + suffix;
    }

    async function postForm(form, data = new FormData(form)) {
        // getAttribute: un campo name="action" ocultaría la propiedad form.action.
        const response = await fetch(form.getAttribute('action'), {
            method: 'POST',
            body: data,
            headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
            credentials: 'same-origin',
        });
        if (response.status === 401) {
            window.location.href = (config.baseUrl || '') + '/login.php';
            throw new Error(t('Inicia sesión para continuar.'));
        }
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || !payload.ok) {
            throw new Error(payload.error || t('No se pudo completar la acción.'));
        }
        return payload;
    }

    /* ---------- Confirmación con diálogo propio ---------- */
    const confirmDialog = $('#confirm-dialog');

    function confirmAction(message, label) {
        if (!confirmDialog || typeof confirmDialog.showModal !== 'function') {
            return Promise.resolve(window.confirm(message));
        }
        $('[data-confirm-text]', confirmDialog).textContent = message;
        $('[data-confirm-ok]', confirmDialog).textContent = label || t('Confirmar');
        confirmDialog.returnValue = '';
        confirmDialog.showModal();
        return new Promise((resolve) => {
            confirmDialog.addEventListener('close', () => resolve(confirmDialog.returnValue === 'ok'), { once: true });
        });
    }

    /* ---------- Me gusta / Guardar ---------- */
    const busy = new WeakSet();

    function setPressed(button, active) {
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', String(active));
    }

    async function toggle(form) {
        if (busy.has(form)) {
            return;
        }
        const kind = form.getAttribute('data-toggle-form');
        const button = $('button', form);
        const card = form.closest('[data-post-id]');
        const postId = card ? card.getAttribute('data-post-id') : '';
        const wasActive = button.getAttribute('aria-pressed') === 'true';

        busy.add(form);
        setPressed(button, !wasActive);
        try {
            const result = await postForm(form);
            // La misma publicación puede aparecer más de una vez en la página.
            $$('[data-post-id="' + postId + '"] [data-toggle-form="' + kind + '"] button').forEach((btn) => {
                setPressed(btn, result.active);
                const count = $('[data-count]', btn);
                if (count) {
                    count.textContent = compactNumber(result.count);
                }
            });
            if (kind === 'save') {
                toast(result.active ? t('Guardado en tu colección') : t('Quitado de guardados'), 'success', 2200);
            }
        } catch (error) {
            setPressed(button, wasActive);
            toast(error.message, 'error');
        } finally {
            busy.delete(form);
        }
    }

    document.addEventListener('submit', async (event) => {
        const form = event.target;
        if (form.matches('[data-confirm]') && !form.dataset.confirmed) {
            event.preventDefault();
            window.Trevix.closeDropdowns();
            if (await confirmAction(form.getAttribute('data-confirm'), form.getAttribute('data-confirm-label'))) {
                form.dataset.confirmed = '1';
                form.submit();
            }
            return;
        }
        if (form.matches('[data-toggle-form]')) {
            event.preventDefault();
            toggle(form);
        }
        if (form.matches('[data-event-form]')) {
            event.preventDefault();
            respondEvent(form);
        }
    });

    /* ---------- Eventos: «Asistiré» / «Me interesa» ---------- */
    async function respondEvent(form) {
        if (busy.has(form)) {
            return;
        }
        const card = form.closest('[data-event-card]');
        busy.add(form);
        try {
            const result = await postForm(form);
            // El mismo evento puede aparecer más de una vez (inicio y Destacados).
            $$('[data-event-card="' + card.getAttribute('data-event-card') + '"]').forEach((el) => {
                $('[data-event-count="going"]', el).textContent = compactNumber(result.going_count);
                $('[data-event-count="interested"]', el).textContent = compactNumber(result.interested_count);
                $$('[data-event-choice]', el).forEach((input) => {
                    const choice = input.getAttribute('data-event-choice');
                    const active = result.viewer_response === choice;
                    input.value = active ? 'none' : choice;
                    const button = $('button', input.form);
                    button.classList.toggle('btn--primary', active);
                    button.classList.toggle('btn--secondary', !active);
                    button.setAttribute('aria-pressed', String(active));
                });
            });
        } catch (error) {
            toast(error.message, 'error');
        } finally {
            busy.delete(form);
        }
    }

    /* ---------- Paginación del feed ---------- */
    const observer = 'IntersectionObserver' in window
        ? new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    loadMore(entry.target);
                }
            });
        }, { rootMargin: '600px 0px' })
        : null;

    async function loadMore(box) {
        const link = $('a', box);
        if (!link || box.dataset.loading) {
            return;
        }
        box.dataset.loading = '1';
        const label = link.textContent;
        link.textContent = t('Cargando…');
        link.setAttribute('aria-busy', 'true');
        try {
            const url = new URL(link.href, window.location.href);
            url.searchParams.set('partial', '1');
            const response = await fetch(url, { headers: { 'X-Requested-With': 'XMLHttpRequest' }, credentials: 'same-origin' });
            if (!response.ok) {
                throw new Error();
            }
            const template = document.createElement('template');
            template.innerHTML = await response.text();
            const nodes = Array.from(template.content.children);
            if (observer) {
                observer.unobserve(box);
            }
            box.replaceWith(template.content);
            nodes.forEach(enhance);
        } catch {
            if (observer) {
                observer.unobserve(box);
            }
            delete box.dataset.loading;
            link.removeAttribute('aria-busy');
            link.textContent = label;
            toast(t('No se pudieron cargar más publicaciones. Inténtalo de nuevo.'), 'error');
        }
    }

    function bindLoadMore(root) {
        const boxes = root.matches && root.matches('[data-load-more]') ? [root] : $$('[data-load-more]', root);
        boxes.forEach((box) => {
            if (box.dataset.bound) {
                return;
            }
            box.dataset.bound = '1';
            const link = $('a', box);
            if (link) {
                link.addEventListener('click', (event) => {
                    event.preventDefault();
                    loadMore(box);
                });
            }
            if (observer) {
                observer.observe(box);
            }
        });
    }

    function enhance(root) {
        if (window.Trevix.initCollapsible) {
            window.Trevix.initCollapsible(root);
        }
        bindLoadMore(root);
    }

    /* ---------- Traducir con IA ---------- */
    const languageNames = { es: 'español', en: 'inglés', pt: 'portugués', fr: 'francés', it: 'italiano', de: 'alemán' };

    document.addEventListener('click', async (event) => {
        const button = event.target.closest('[data-translate]');
        if (!button || button.disabled) {
            return;
        }
        const box = button.closest('[data-translate-box]');
        const output = $('[data-translation]', box);
        const label = $('[data-translate-label]', button);
        const show = (visible) => {
            output.hidden = !visible;
            button.setAttribute('aria-expanded', String(visible));
            label.textContent = visible ? t('Ocultar traducción') : t('Traducir');
        };
        if (!output.hidden || output.dataset.loaded) {
            show(output.hidden);
            return;
        }
        button.disabled = true;
        label.textContent = t('Traduciendo…');
        try {
            const data = new FormData();
            data.append('post_id', button.getAttribute('data-translate'));
            data.append('lang', config.lang || 'es');
            const result = await window.Trevix.api('api/translate.php', { method: 'POST', data });
            output.replaceChildren();
            const caption = document.createElement('p');
            caption.className = 'post__translation-caption';
            const source = result.source_lang ? t(languageNames[result.source_lang] || result.source_lang.toUpperCase()) : null;
            caption.textContent = result.same_language
                ? t('Esta publicación ya está en tu idioma.')
                : (source ? t('Traducido del {lang} con IA', { lang: source }) : t('Traducido con IA'));
            output.append(caption);
            if (!result.same_language) {
                const text = document.createElement('p');
                text.className = 'post__translation-text';
                text.textContent = result.body;
                output.append(text);
            }
            output.dataset.loaded = '1';
            show(true);
        } catch (error) {
            label.textContent = t('Traducir');
            toast(error.message, 'error');
        } finally {
            button.disabled = false;
        }
    });

    bindLoadMore(document);
    Object.assign(window.Trevix, { enhancePosts: enhance, postForm, confirmAction, compactNumber });
})();
