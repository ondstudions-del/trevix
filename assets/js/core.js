/*
 * TREVIX · Núcleo de cliente
 * Utilidades compartidas por todas las páginas: configuración, toasts, menús desplegables,
 * diálogos, portapapeles, contadores de caracteres y vista previa de imágenes.
 */
(function () {
    'use strict';

    const configEl = document.getElementById('trevix-config');
    const config = configEl ? JSON.parse(configEl.textContent) : {};

    /* Textos en el idioma de la interfaz: t('Hola, {name}', { name }) (el diccionario llega en trevix-config). */
    const dictionary = config.i18n || {};
    function t(text, params) {
        let out = Object.prototype.hasOwnProperty.call(dictionary, text) ? dictionary[text] : text;
        if (params) {
            Object.keys(params).forEach((key) => {
                out = out.split('{' + key + '}').join(String(params[key]));
            });
        }
        return out;
    }
    const tn = (n, one, many, params) => t(n === 1 ? one : many, Object.assign({ n }, params || {}));

    const $ = (selector, context = document) => context.querySelector(selector);
    const $$ = (selector, context = document) => Array.from(context.querySelectorAll(selector));

    const ICONS = {
        success: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
        error: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
        info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    };

    /* ---------- Preferencias locales ---------- */
    const prefs = {
        all() {
            try {
                return JSON.parse(localStorage.getItem('trevix.prefs') || '{}');
            } catch {
                return {};
            }
        },
        get(key) {
            return this.all()[key];
        },
        set(key, value) {
            const data = this.all();
            data[key] = value;
            try {
                localStorage.setItem('trevix.prefs', JSON.stringify(data));
            } catch {
                /* almacenamiento no disponible */
            }
            this.apply(data);
        },
        apply(data = this.all()) {
            const root = document.documentElement;
            root.classList.toggle('reduce-motion', Boolean(data.reduceMotion));
            if (data.fontSize === 'large' || data.fontSize === 'xlarge') {
                root.setAttribute('data-font-size', data.fontSize);
            } else {
                root.removeAttribute('data-font-size');
            }
        },
    };

    /* ---------- Utilidades ---------- */
    function formatBytes(bytes) {
        if (bytes < 1024 * 1024) {
            return Math.max(1, Math.round(bytes / 1024)) + ' KB';
        }
        return (bytes / (1024 * 1024)).toFixed(1).replace('.', config.lang === 'en' ? '.' : ',') + ' MB';
    }

    function toast(message, type = 'info', timeout = 3200) {
        const region = document.getElementById('toast-region');
        if (!region) {
            return;
        }
        const el = document.createElement('div');
        el.className = 'toast toast--' + type;
        el.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
            + 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[type] || ICONS.info) + '</svg>';
        const text = document.createElement('span');
        text.textContent = message;
        el.appendChild(text);
        region.appendChild(el);

        window.setTimeout(() => {
            el.classList.add('is-leaving');
            el.addEventListener('animationend', () => el.remove(), { once: true });
        }, timeout);
    }

    /** Cliente HTTP para la API interna: envía siempre el token CSRF y espera JSON. */
    async function api(path, { method = 'GET', data = null } = {}) {
        const headers = {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-CSRF-Token': config.csrfToken || '',
        };
        let body = null;
        if (data instanceof FormData) {
            body = data;
        } else if (data !== null) {
            headers['Content-Type'] = 'application/json';
            body = JSON.stringify(data);
        }

        const response = await fetch((config.baseUrl || '') + '/' + path.replace(/^\//, ''), {
            method,
            headers,
            body,
            credentials: 'same-origin',
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || payload.ok === false) {
            throw new Error(payload.error || t('No se pudo completar la solicitud.'));
        }
        return payload;
    }

    async function copyText(text) {
        try {
            await navigator.clipboard.writeText(text);
        } catch {
            const area = document.createElement('textarea');
            area.value = text;
            area.setAttribute('readonly', '');
            area.className = 'sr-only';
            document.body.appendChild(area);
            area.select();
            document.execCommand('copy');
            area.remove();
        }
    }

    /* ---------- Menús desplegables ---------- */
    function closeDropdowns(except = null) {
        $$('[data-dropdown-trigger][aria-expanded="true"]').forEach((trigger) => {
            if (trigger === except) {
                return;
            }
            trigger.setAttribute('aria-expanded', 'false');
            const menu = trigger.parentElement.querySelector('.dropdown__menu');
            if (menu) {
                menu.hidden = true;
            }
        });
    }

    function menuItems(menu) {
        return $$('.dropdown__item:not(:disabled)', menu);
    }

    document.addEventListener('click', (event) => {
        const trigger = event.target.closest('[data-dropdown-trigger]');
        if (trigger) {
            const menu = trigger.parentElement.querySelector('.dropdown__menu');
            const open = trigger.getAttribute('aria-expanded') !== 'true';
            closeDropdowns(trigger);
            trigger.setAttribute('aria-expanded', String(open));
            if (menu) {
                menu.hidden = !open;
                if (open && event.detail === 0) {
                    const first = menuItems(menu)[0];
                    if (first) {
                        first.focus();
                    }
                }
            }
            return;
        }
        if (!event.target.closest('.dropdown__menu')) {
            closeDropdowns();
        }
    });

    document.addEventListener('keydown', (event) => {
        const menu = event.target.closest && event.target.closest('.dropdown__menu');
        if (event.key === 'Escape') {
            const openTrigger = $('[data-dropdown-trigger][aria-expanded="true"]');
            if (openTrigger) {
                closeDropdowns();
                openTrigger.focus();
            }
            return;
        }
        if (menu && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
            event.preventDefault();
            const items = menuItems(menu);
            const index = items.indexOf(document.activeElement);
            const nextIndex = event.key === 'ArrowDown'
                ? (index + 1) % items.length
                : (index - 1 + items.length) % items.length;
            if (items[nextIndex]) {
                items[nextIndex].focus();
            }
        }
    });

    /* ---------- Diálogos ---------- */
    document.addEventListener('click', (event) => {
        const closer = event.target.closest('[data-close-dialog]');
        if (closer) {
            const dialog = closer.closest('dialog');
            if (dialog) {
                dialog.close();
            }
            return;
        }
        if (event.target instanceof HTMLDialogElement && event.target.open) {
            const rect = event.target.getBoundingClientRect();
            const inside = event.clientX >= rect.left && event.clientX <= rect.right
                && event.clientY >= rect.top && event.clientY <= rect.bottom;
            if (!inside || event.target.classList.contains('lightbox')) {
                event.target.close();
            }
        }
    });

    /* ---------- Portapapeles ---------- */
    document.addEventListener('click', async (event) => {
        const textButton = event.target.closest('[data-copy-text]');
        const urlButton = event.target.closest('[data-copy-url]');
        if (!textButton && !urlButton) {
            return;
        }
        if (textButton) {
            await copyText(textButton.getAttribute('data-copy-text'));
            closeDropdowns();
            toast(t('Texto copiado al portapapeles'), 'success');
            return;
        }
        await copyText(new URL(urlButton.getAttribute('data-copy-url'), window.location.href).href);
        toast(t('Enlace copiado al portapapeles'), 'success');
    });

    /* ---------- Formularios ---------- */
    function autosize(textarea) {
        textarea.style.height = 'auto';
        textarea.style.height = textarea.scrollHeight + 'px';
    }

    function updateCharCount(input) {
        const target = document.querySelector(input.getAttribute('data-char-count'));
        if (!target) {
            return;
        }
        const max = Number(input.getAttribute('maxlength')) || 0;
        target.textContent = input.value.length + ' / ' + max;
    }

    document.addEventListener('input', (event) => {
        const el = event.target;
        if (el.matches('[data-autosize]')) {
            autosize(el);
        }
        if (el.matches('[data-char-count]')) {
            updateCharCount(el);
        }
        if (el.matches('[data-username-input]')) {
            const cleaned = el.value.toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 30);
            if (cleaned !== el.value) {
                el.value = cleaned;
            }
        }
        if (el.matches('[data-filter-input]')) {
            const list = document.querySelector(el.getAttribute('data-filter-input'));
            const term = el.value.trim().toLowerCase();
            if (list) {
                $$('[data-filter-text]', list).forEach((item) => {
                    item.hidden = term !== '' && !item.getAttribute('data-filter-text').includes(term);
                });
            }
        }
    });

    function validateImage(file, maxBytesOverride) {
        const rules = (config.uploads && config.uploads.image) || { mimes: [], maxBytes: 0 };
        const maxBytes = maxBytesOverride || rules.maxBytes;
        if (!rules.mimes.includes(file.type)) {
            return t('Formato no permitido. Usa JPG, PNG, WEBP o GIF.');
        }
        if (file.size > maxBytes) {
            return t('La imagen supera el máximo de {size}.', { size: formatBytes(maxBytes) });
        }
        return null;
    }

    document.addEventListener('change', (event) => {
        const input = event.target;
        if (!input.matches('[data-image-preview]') || !input.files || !input.files[0]) {
            return;
        }
        const file = input.files[0];
        const error = validateImage(file, Number(input.getAttribute('data-max-bytes')) || 0);
        if (error) {
            input.value = '';
            toast(error, 'error');
            return;
        }
        const key = input.getAttribute('data-image-preview');
        const img = document.querySelector('[data-preview="' + key + '"]');
        const fallback = document.querySelector('[data-preview-fallback="' + key + '"]');
        if (img) {
            if (img.dataset.objectUrl) {
                URL.revokeObjectURL(img.dataset.objectUrl);
            }
            img.dataset.objectUrl = URL.createObjectURL(file);
            img.src = img.dataset.objectUrl;
            img.hidden = false;
        }
        if (fallback) {
            fallback.hidden = true;
        }
    });

    /* ---------- Aviso de vista previa ---------- */
    document.addEventListener('click', (event) => {
        if (!event.target.closest('[data-dismiss-banner]')) {
            return;
        }
        document.documentElement.classList.add('preview-banner-hidden');
        try {
            localStorage.setItem('trevix.previewBanner', 'hidden');
        } catch {
            /* almacenamiento no disponible */
        }
    });

    document.addEventListener('DOMContentLoaded', () => {
        $$('[data-autosize]').forEach(autosize);
        $$('[data-char-count]').forEach(updateCharCount);
    });

    window.Trevix = { config, $, $$, toast, api, prefs, formatBytes, copyText, closeDropdowns, t, tn };
})();
