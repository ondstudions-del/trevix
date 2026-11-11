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

    const { $, $$, toast, copyText, closeDropdowns, t } = window.Trevix;
    const dialog = $('#share-dialog');
    if (!dialog || typeof dialog.showModal !== 'function') {
        return;
    }
    const hint = $('[data-share-hint]', dialog);
    const native = $('[data-share-net="native"]', dialog);
    let current = { url: '', title: '' };

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
        current = { url, title };
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
