/*
 * TREVIX · Mensajes privados
 * Envía sin recargar (texto e imagen), consulta mensajes nuevos cada pocos segundos mientras la
 * pestaña está visible, marca "Visto", carga mensajes anteriores y elimina mensajes propios.
 * Sin JavaScript, los mismos formularios funcionan con recarga completa.
 */
// Se inicia en DOMContentLoaded: postForm y confirmAction los aporta posts.js, que se carga después.
document.addEventListener('DOMContentLoaded', () => {
    'use strict';

    const { $, $$, toast, config, postForm, confirmAction, formatBytes } = window.Trevix;
    const POLL_MS = 4000;

    const scroller = $('[data-chat-scroll]');
    const list = $('[data-chat-list]');
    const seen = $('[data-chat-seen]');
    const form = $('[data-chat-form]');
    if (!scroller || !list) {
        return;
    }

    const pollUrl = scroller.getAttribute('data-chat-poll');
    let lastId = Number(scroller.getAttribute('data-last-id') || 0);
    let firstId = Number(scroller.getAttribute('data-first-id') || 0);
    let polling = false;
    let timer = null;

    const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 140;
    const toBottom = () => {
        scroller.scrollTop = scroller.scrollHeight;
    };

    function parse(html) {
        const template = document.createElement('template');
        template.innerHTML = html.trim();
        return Array.from(template.content.children);
    }

    function append(html) {
        parse(html).forEach((node) => {
            const id = node.getAttribute('data-message-id');
            if (id && list.querySelector('[data-message-id="' + id + '"]')) {
                return;
            }
            list.appendChild(node);
        });
    }

    /** Id del último mensaje si es propio y no está eliminado (solo ahí se muestra "Visto"). */
    function lastOwnId() {
        const last = list.lastElementChild;
        if (!last || !last.hasAttribute('data-mine') || last.classList.contains('is-deleted')) {
            return 0;
        }
        return Number(last.getAttribute('data-message-id'));
    }

    function updateSeen(seenId) {
        if (!seen) {
            return;
        }
        if (typeof seenId === 'number') {
            seen.setAttribute('data-seen-id', String(seenId));
        }
        const own = lastOwnId();
        seen.hidden = !(own > 0 && Number(seen.getAttribute('data-seen-id')) >= own);
    }

    function markDeleted(id) {
        const row = list.querySelector('[data-message-id="' + id + '"]');
        if (!row || row.classList.contains('is-deleted')) {
            return;
        }
        row.classList.add('is-deleted');
        $$('.bubble, .bubble__media, .bubble__delete-form', row).forEach((el) => el.remove());
        const placeholder = document.createElement('p');
        placeholder.className = 'bubble bubble--deleted';
        placeholder.textContent = 'Mensaje eliminado';
        row.insertBefore(placeholder, row.firstChild);
    }

    function updatePresence(online) {
        const dot = $('[data-chat-presence]');
        const status = $('[data-chat-status]');
        if (dot) {
            dot.hidden = !online;
        }
        if (status) {
            status.textContent = online ? 'En línea' : status.getAttribute('data-offline');
        }
    }

    async function poll() {
        if (!pollUrl || polling || document.hidden) {
            return;
        }
        polling = true;
        try {
            const params = new URLSearchParams({
                action: 'poll',
                c: scroller.getAttribute('data-conversation'),
                after: String(lastId),
                from: String(firstId || lastId),
                read: document.visibilityState === 'visible' ? '1' : '0',
            });
            const response = await fetch(pollUrl + '?' + params.toString(), {
                headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
                credentials: 'same-origin',
            });
            if (response.status === 401 || response.status === 404) {
                stop();
                return;
            }
            const data = await response.json();
            if (!data.ok) {
                return;
            }
            if (data.html) {
                const stick = nearBottom();
                append(data.html);
                if (stick) {
                    toBottom();
                }
            }
            lastId = Math.max(lastId, Number(data.last_id) || 0);
            if (!firstId && lastId) {
                firstId = lastId;
            }
            (data.deleted || []).forEach(markDeleted);
            updateSeen(Number(data.seen_id) || 0);
            updatePresence(Boolean(data.online));
            if (window.Trevix.setBadge) {
                window.Trevix.setBadge('messages', Number(data.unread) || 0);
            }
        } catch {
            /* sin conexión: se reintenta en el siguiente ciclo */
        } finally {
            polling = false;
        }
    }

    function stop() {
        if (timer) {
            window.clearInterval(timer);
            timer = null;
        }
    }

    function start() {
        if (!pollUrl) {
            return;
        }
        stop();
        timer = window.setInterval(poll, POLL_MS);
    }

    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            stop();
        } else {
            poll();
            start();
        }
    });

    /* ---------- Adjuntar imagen ---------- */
    const fileInput = form ? $('[data-chat-image]', form) : null;
    const attachment = form ? $('[data-chat-attachment]', form) : null;

    function clearAttachment() {
        if (!fileInput || !attachment) {
            return;
        }
        fileInput.value = '';
        const img = $('[data-chat-attachment-img]', attachment);
        if (img.dataset.objectUrl) {
            URL.revokeObjectURL(img.dataset.objectUrl);
            delete img.dataset.objectUrl;
        }
        img.removeAttribute('src');
        attachment.hidden = true;
    }

    if (fileInput && attachment) {
        fileInput.addEventListener('change', () => {
            const file = fileInput.files && fileInput.files[0];
            if (!file) {
                clearAttachment();
                return;
            }
            const rules = (config.uploads && config.uploads.image) || { mimes: [], maxBytes: 0 };
            if (!rules.mimes.includes(file.type)) {
                clearAttachment();
                toast('Solo puedes enviar imágenes JPG, PNG, WEBP o GIF.', 'error');
                return;
            }
            if (rules.maxBytes && file.size > rules.maxBytes) {
                clearAttachment();
                toast('La imagen supera el máximo de ' + formatBytes(rules.maxBytes) + '.', 'error');
                return;
            }
            const img = $('[data-chat-attachment-img]', attachment);
            if (img.dataset.objectUrl) {
                URL.revokeObjectURL(img.dataset.objectUrl);
            }
            img.dataset.objectUrl = URL.createObjectURL(file);
            img.src = img.dataset.objectUrl;
            $('[data-chat-attachment-name]', attachment).textContent = file.name + ' · ' + formatBytes(file.size);
            attachment.hidden = false;
            if (songField && window.Trevix.music && window.Trevix.music.hasSong(songField)) {
                window.Trevix.music.clearField(songField);
            }
        });
        $('[data-chat-attachment-clear]', attachment).addEventListener('click', clearAttachment);
    }

    /* ---------- Enviar una canción (un mensaje lleva una imagen o una canción) ---------- */
    const songField = form ? $('[data-song-field]', form) : null;
    if (songField) {
        songField.addEventListener('trevix:song-change', (event) => {
            if (event.detail.song) {
                clearAttachment();
            }
        });
    }
    const hasSong = () => Boolean(songField && window.Trevix.music && window.Trevix.music.hasSong(songField));

    /* ---------- Enviar ---------- */
    if (form) {
        const input = $('[data-chat-input]', form);
        const submit = $('button[type="submit"]', form);
        let sending = false;

        input.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
                event.preventDefault();
                form.requestSubmit();
            }
        });

        form.addEventListener('submit', async (event) => {
            event.preventDefault();
            if (sending) {
                return;
            }
            const hasFile = fileInput && fileInput.files && fileInput.files.length > 0;
            const withSong = hasSong();
            if (input.value.trim() === '' && !hasFile && !withSong) {
                input.focus();
                return;
            }
            sending = true;
            submit.disabled = true;
            form.classList.add('is-busy');
            try {
                const data = await postForm(form);
                if ($('input[name="to"]', form)) {
                    window.location.href = data.url;
                    return;
                }
                append(data.html);
                lastId = Math.max(lastId, Number(data.message_id) || 0);
                if (!firstId) {
                    firstId = lastId;
                }
                const preview = $('.conv.is-active .conv__preview');
                if (preview) {
                    const text = input.value.trim().replace(/\s+/g, ' ') || (withSong ? 'Canción' : 'Foto');
                    preview.textContent = 'Tú: ' + (text.length > 80 ? text.slice(0, 79) + '…' : text);
                }
                input.value = '';
                input.style.height = '';
                clearAttachment();
                if (withSong) {
                    window.Trevix.music.clearField(songField);
                }
                updateSeen();
                toBottom();
            } catch (error) {
                toast(error.message, 'error');
            } finally {
                sending = false;
                submit.disabled = false;
                form.classList.remove('is-busy');
                input.focus();
            }
        });
    }

    /* ---------- Eliminar mensaje propio ---------- */
    document.addEventListener('submit', async (event) => {
        const deleteForm = event.target.closest('[data-message-delete]');
        if (!deleteForm) {
            return;
        }
        event.preventDefault();
        const ok = await confirmAction('¿Eliminar este mensaje? En la conversación quedará la marca «Mensaje eliminado».', 'Eliminar');
        if (!ok) {
            return;
        }
        try {
            const data = await postForm(deleteForm);
            const row = deleteForm.closest('[data-message-id]');
            const replacement = parse(data.html)[0];
            if (row && replacement) {
                row.replaceWith(replacement);
            }
            updateSeen();
        } catch (error) {
            toast(error.message, 'error');
        }
    });

    /* ---------- Mensajes anteriores ---------- */
    scroller.addEventListener('click', async (event) => {
        const link = event.target.closest('[data-chat-older]');
        if (!link) {
            return;
        }
        event.preventDefault();
        if (link.dataset.loading) {
            return;
        }
        link.dataset.loading = '1';
        const label = link.textContent;
        link.textContent = 'Cargando…';
        try {
            const url = new URL(link.href, window.location.href);
            url.searchParams.set('partial', '1');
            const response = await fetch(url.toString(), { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } });
            if (!response.ok) {
                throw new Error();
            }
            const nodes = parse(await response.text());
            const previousHeight = scroller.scrollHeight;
            nodes.reverse().forEach((node) => list.insertBefore(node, list.firstChild));
            scroller.scrollTop += scroller.scrollHeight - previousHeight;

            const pageSize = Number(config.limits && config.limits.messages_page) || 40;
            if (nodes.length < pageSize || !list.firstElementChild) {
                link.closest('.chat__older').remove();
                return;
            }
            firstId = Number(list.firstElementChild.getAttribute('data-message-id')) || firstId;
            url.searchParams.delete('partial');
            url.searchParams.set('before', String(firstId));
            link.href = url.toString();
            link.textContent = label;
            delete link.dataset.loading;
        } catch {
            link.textContent = label;
            delete link.dataset.loading;
            toast('No se pudieron cargar los mensajes anteriores.', 'error');
        }
    });

    /* ---------- Inicio ---------- */
    if (!window.location.search.includes('before=')) {
        toBottom();
    }
    updateSeen();
    start();
});
