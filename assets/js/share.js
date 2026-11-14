/*
 * TREVIX · Compartir fuera de TREVIX
 * Los botones [data-share-out="URL"] (data-share-title opcional) abren el diálogo con X, WhatsApp, TikTok,
 * Facebook, Telegram, correo, copiar enlace y, si el navegador lo permite, el menú del sistema.
 */
(function () {
    'use strict';

    const { $, t } = window.Trevix;
    const isAndroid = /Android/i.test(navigator.userAgent);
    if (isAndroid) {
        document.querySelectorAll('[data-android-href]:not([data-app-open-link])').forEach((a) => {
            a.href = a.dataset.androidHref;
        });
    }
    const banner = $('[data-app-open]');
    if (!banner) {
        return;
    }
    const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent)
        || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    let dismissed = false;
    try {
        dismissed = localStorage.getItem('trevix.appOpen') === 'hidden';
    } catch (error) {
        dismissed = false;
    }
    if ((!isIOS && !isAndroid) || dismissed) {
        return;
    }
    const link = $('[data-app-open-link]', banner);
    if (isAndroid) {
        link.href = link.dataset.androidHref;
        $('[data-app-open-name]', banner).textContent = t('TREVIX para Android');
    }
    banner.hidden = false;
    $('[data-app-open-close]', banner).addEventListener('click', () => {
        banner.hidden = true;
        try {
            localStorage.setItem('trevix.appOpen', 'hidden');
        } catch (error) {
            /* Sin almacenamiento solo se oculta en esta página. */
        }
    });
    link.addEventListener('click', () => {
        // Si la app no está instalada el teléfono no la abre: se avisa en lugar de dejar el botón sin respuesta.
        const timer = window.setTimeout(() => {
            if (!document.hidden) {
                window.Trevix.toast(t('Instala TREVIX en tu {device} para abrir este enlace en la app.', { device: isAndroid ? 'Android' : 'iPhone' }), 'info', 4500);
            }
        }, 1600);
        document.addEventListener('visibilitychange', () => window.clearTimeout(timer), { once: true });
    });
})();

(function () {
    'use strict';

    const { $, $$, toast, copyText, closeDropdowns, t, config } = window.Trevix;
    const dialog = $('#share-dialog');
    if (!dialog || typeof dialog.showModal !== 'function') {
        return;
    }
    const hint = $('[data-share-hint]', dialog);
    const native = $('[data-share-net="native"]', dialog);
    let current = { url: '', title: '', postId: '' };

    /** Compartir una publicación fuera de TREVIX cuenta para los intereses de «Para ti» (una vez por diálogo). */
    function signalShare() {
        if (!current.postId || !navigator.sendBeacon || !config.csrfToken) {
            return;
        }
        const data = new FormData();
        data.append('_csrf', config.csrfToken);
        data.append('post_id', current.postId);
        data.append('kind', 'share');
        navigator.sendBeacon((config.baseUrl || '') + '/api/signals.php', data);
        current.postId = '';
    }

    const enc = encodeURIComponent;
    const builders = {
        x: (u, s) => 'https://x.com/intent/post?text=' + enc(s) + '&url=' + enc(u),
        whatsapp: (u, s) => 'https://wa.me/?text=' + enc(s ? s + ' ' + u : u),
        facebook: (u) => 'https://www.facebook.com/sharer/sharer.php?u=' + enc(u),
        telegram: (u, s) => 'https://t.me/share/url?url=' + enc(u) + '&text=' + enc(s),
        mail: (u, s) => 'mailto:?subject=' + enc(s || t('Mira esto en TREVIX')) + '&body=' + enc((s ? s + '\n\n' : '') + u),
    };

    function showHint(text) {
        hint.textContent = text;
        hint.hidden = !text;
    }

    function open(trigger) {
        const url = new URL(trigger.getAttribute('data-share-out'), window.location.href).href;
        const title = (trigger.getAttribute('data-share-title') || '').trim();
        current = { url, title, postId: trigger.getAttribute('data-share-signal') || '' };
        $('[data-share-target]', dialog).textContent = title || url;
        $$('a[data-share-net]', dialog).forEach((a) => {
            const build = builders[a.getAttribute('data-share-net')];
            if (build) {
                a.href = build(url, title);
            }
        });
        native.hidden = typeof navigator.share !== 'function';
        showHint('');
        closeDropdowns();
        dialog.showModal();
    }

    document.addEventListener('click', (event) => {
        const trigger = event.target.closest('[data-share-out]');
        if (!trigger) {
            return;
        }
        event.preventDefault();
        open(trigger);
    });

    dialog.addEventListener('click', async (event) => {
        const net = event.target.closest('[data-share-net]');
        if (!net) {
            return;
        }
        const kind = net.getAttribute('data-share-net');
        signalShare();
        if (kind === 'copy') {
            await copyText(current.url);
            toast(t('Enlace copiado al portapapeles'), 'success');
            dialog.close();
        } else if (kind === 'tiktok') {
            await copyText(current.url);
            showHint(t('Copiamos el enlace. TikTok no recibe enlaces desde la web: pégalo en un mensaje o en tu biografía.'));
            window.open('https://www.tiktok.com/messages', '_blank', 'noopener');
        } else if (kind === 'native') {
            try {
                await navigator.share({ title: current.title || 'TREVIX', text: current.title, url: current.url });
                dialog.close();
            } catch (error) {
                if (error && error.name !== 'AbortError') {
                    toast(t('No se pudo abrir el menú para compartir.'), 'error');
                }
            }
        } else {
            window.setTimeout(() => dialog.close(), 150);
        }
    });
})();

/* Enviar una publicación o un reel por mensaje: [data-send-post="ID"] abre el diálogo con chats y personas. */
(function () {
    'use strict';

    const { $, toast, closeDropdowns, t, config } = window.Trevix;
    const dialog = $('#send-post-dialog');
    if (!dialog || typeof dialog.showModal !== 'function' || !config.csrfToken) {
        return;
    }
    const MAX = 10;
    const endpoint = (config.baseUrl || '') + '/api/messages.php';
    const form = $('[data-send-post-form]', dialog);
    const list = $('[data-send-post-list]', dialog);
    const empty = $('[data-send-post-empty]', dialog);
    const search = $('[data-send-post-search]', dialog);
    const body = $('[data-send-post-body]', dialog);
    const error = $('[data-send-post-error]', dialog);
    const submit = $('[data-send-post-submit]', dialog);
    const count = $('[data-send-post-count]', dialog);
    let postId = '';
    let chosen = new Map();
    let timer = 0;
    let loadSeq = 0;
    let sending = false;

    function showError(text) {
        error.textContent = text;
        error.hidden = !text;
    }

    function refresh() {
        submit.disabled = sending || chosen.size === 0;
        count.textContent = chosen.size > 1 ? t('Enviar a {count}', { count: chosen.size }) : t('Enviar');
    }

    function render(items) {
        list.replaceChildren();
        items.forEach((item) => {
            const li = document.createElement('li');
            const label = document.createElement('label');
            label.className = 'send-post-dialog__item';
            const box = document.createElement('input');
            box.type = 'checkbox';
            box.value = item.target;
            box.checked = chosen.has(item.target);
            box.addEventListener('change', () => {
                if (box.checked && chosen.size >= MAX) {
                    box.checked = false;
                    toast(t('Puedes enviarlo a {count} chats a la vez como máximo.', { count: MAX }), 'info');
                    return;
                }
                if (box.checked) {
                    chosen.set(item.target, item.name);
                } else {
                    chosen.delete(item.target);
                }
                refresh();
            });
            const avatar = document.createElement('span');
            avatar.className = 'send-post-dialog__avatar';
            avatar.innerHTML = item.avatar;
            const text = document.createElement('span');
            text.className = 'send-post-dialog__who';
            const name = document.createElement('strong');
            name.textContent = item.name;
            const sub = document.createElement('small');
            sub.textContent = item.group ? t('Grupo') : '@' + item.username;
            text.append(name, sub);
            label.append(avatar, text, box);
            li.append(label);
            list.append(li);
        });
        empty.hidden = items.length > 0;
        empty.textContent = search.value.trim() ? t('No encontramos chats ni personas con ese nombre.') : t('Aún no tienes chats. Busca a alguien para enviárselo.');
    }

    async function load() {
        const seq = ++loadSeq;
        const params = new URLSearchParams({ action: 'share_targets', q: search.value.trim() });
        try {
            const response = await fetch(endpoint + '?' + params.toString(), { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } });
            const data = await response.json();
            if (seq !== loadSeq) {
                return;
            }
            if (!response.ok || !data.ok) {
                throw new Error(data.error || '');
            }
            render(data.items || []);
        } catch (err) {
            if (seq === loadSeq) {
                render([]);
                showError(t('No se pudieron cargar tus chats. Inténtalo de nuevo.'));
            }
        }
    }

    function open(trigger) {
        postId = trigger.getAttribute('data-send-post') || '';
        chosen = new Map();
        $('[data-send-post-target]', dialog).textContent = trigger.getAttribute('data-send-label') || '';
        search.value = '';
        body.value = '';
        showError('');
        list.replaceChildren();
        empty.hidden = true;
        refresh();
        closeDropdowns();
        dialog.showModal();
        load();
    }

    document.addEventListener('click', (event) => {
        const trigger = event.target.closest('[data-send-post]');
        if (trigger) {
            event.preventDefault();
            open(trigger);
        }
    });

    search.addEventListener('input', () => {
        window.clearTimeout(timer);
        timer = window.setTimeout(load, 250);
    });

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (sending || chosen.size === 0 || !postId) {
            return;
        }
        sending = true;
        showError('');
        refresh();
        const failed = [];
        let sent = 0;
        for (const [target, name] of chosen) {
            const data = new FormData();
            data.append('_csrf', config.csrfToken);
            data.append('action', 'send');
            data.append(target.startsWith('c:') ? 'c' : 'to', target.slice(2));
            data.append('shared_post', postId);
            data.append('body', body.value.trim());
            try {
                const response = await fetch(endpoint, {
                    method: 'POST',
                    body: data,
                    headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
                    credentials: 'same-origin',
                });
                const result = await response.json();
                if (!response.ok || !result.ok) {
                    throw new Error(result.error || '');
                }
                sent += 1;
                chosen.delete(target);
            } catch (err) {
                failed.push(name + (err.message ? ': ' + err.message : ''));
            }
        }
        sending = false;
        if (failed.length === 0) {
            dialog.close();
            toast(sent > 1 ? t('Enviado a {count} chats.', { count: sent }) : t('Enviado.'), 'success');
            return;
        }
        if (sent > 0) {
            toast(sent > 1 ? t('Enviado a {count} chats.', { count: sent }) : t('Enviado.'), 'success');
        }
        showError(t('No se pudo enviar a:') + ' ' + failed.join(' · '));
        load();
        refresh();
    });
})();
