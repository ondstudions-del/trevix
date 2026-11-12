/*
 * TREVIX · Avisos en vivo
 * Consulta periódicamente (solo con la pestaña visible) cuántas notificaciones y chats hay sin leer
 * y actualiza los contadores de la navegación. También marca todo como leído sin recargar.
 * Cada consulta renueva la presencia «en línea»; al cerrar u ocultar la pestaña se avisa con sendBeacon.
 */
(function () {
    'use strict';

    const { $, $$, api, toast, t, config } = window.Trevix;
    const INTERVAL = 20000;
    let timer = null;

    function setBadge(key, count) {
        $$('[data-badge="' + key + '"]').forEach((holder) => {
            const dot = holder.getAttribute('data-badge-style') === 'dot';
            let badge = $(dot ? '.badge-dot' : '.badge-count', holder);
            if (!count || count <= 0) {
                if (badge) {
                    badge.remove();
                }
                return;
            }
            if (!badge) {
                badge = document.createElement('span');
                badge.className = dot ? 'badge-dot' : 'badge-count';
                holder.appendChild(badge);
            }
            if (dot) {
                badge.setAttribute('aria-hidden', 'true');
            } else {
                badge.textContent = count > 99 ? '99+' : String(count);
                badge.setAttribute('aria-label', t('{n} sin leer', { n: count }));
            }
        });
    }

    let last = 0;
    async function refresh() {
        if (document.hidden || Date.now() - last < 3000) {
            return;
        }
        last = Date.now();
        try {
            const data = await api('api/notifications.php?action=counts');
            setBadge('notifications', data.notifications);
            setBadge('messages', data.messages);
        } catch {
            /* sin conexión o sesión cerrada: se reintenta en el siguiente ciclo */
        }
    }

    function stop() {
        if (timer) {
            window.clearInterval(timer);
            timer = null;
        }
    }

    function start() {
        stop();
        timer = window.setInterval(refresh, INTERVAL);
    }

    function away() {
        if (!navigator.sendBeacon || !config.csrfToken) {
            return;
        }
        const data = new FormData();
        data.append('_csrf', config.csrfToken);
        data.append('action', 'away');
        navigator.sendBeacon((config.baseUrl || '') + '/api/notifications.php', data);
    }

    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            stop();
        } else {
            refresh();
            start();
        }
    });
    window.addEventListener('pagehide', away);
    window.addEventListener('focus', refresh);
    start();

    /* ---------- Marcar todo como leído ---------- */
    document.addEventListener('submit', async (event) => {
        const form = event.target.closest('[data-read-all]');
        if (!form || !window.Trevix.postForm) {
            return;
        }
        event.preventDefault();
        const button = $('button', form);
        button.disabled = true;
        try {
            const data = await window.Trevix.postForm(form);
            $$('[data-notif].is-unread').forEach((item) => {
                if ($('[data-request-actions]', item)) {
                    return;
                }
                item.classList.remove('is-unread');
                const dot = $('.notif__dot', item);
                if (dot) {
                    dot.remove();
                }
            });
            setBadge('notifications', data.notifications);
            form.remove();
            toast(t('Marcaste todas las notificaciones como leídas.'), 'success');
        } catch (error) {
            button.disabled = false;
            toast(error.message, 'error');
        }
    });

    Object.assign(window.Trevix, { setBadge, refreshBadges: refresh });
})();
