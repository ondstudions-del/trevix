/*
 * TREVIX · Mensajes privados
 * Envía sin recargar (texto al instante; imagen, nota de voz —también de una sola vez— o GIF), consulta mensajes
 * nuevos cada pocos segundos mientras la pestaña está visible, marca "Visto", reacciona con las reacciones rápidas
 * propias, carga mensajes anteriores y elimina mensajes propios.
 * Sin JavaScript, los mismos formularios funcionan con recarga completa.
 */
// Se inicia en DOMContentLoaded: postForm y confirmAction los aporta posts.js, que se carga después.
document.addEventListener('DOMContentLoaded', () => {
    'use strict';

    const { $, $$, toast, config, postForm, confirmAction, formatBytes, t } = window.Trevix;
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
        placeholder.textContent = t('Mensaje eliminado');
        row.insertBefore(placeholder, row.firstChild);
    }

    function updatePresence(online) {
        const dot = $('[data-chat-presence]');
        const status = $('[data-chat-status]');
        if (dot) {
            dot.hidden = !online;
        }
        if (status) {
            status.textContent = online ? t('En línea') : status.getAttribute('data-offline');
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
                toast(t('Solo puedes enviar imágenes JPG, PNG, WEBP o GIF.'), 'error');
                return;
            }
            if (rules.maxBytes && file.size > rules.maxBytes) {
                clearAttachment();
                toast(t('La imagen supera el máximo de {size}.', { size: formatBytes(rules.maxBytes) }), 'error');
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
            clearGif();
            voice.discard();
        });
        $('[data-chat-attachment-clear]', attachment).addEventListener('click', clearAttachment);
    }

    /* ---------- GIF o sticker (un mensaje lleva una imagen, una nota de voz o un GIF) ---------- */
    const gifField = form ? $('[data-gif-field]', form) : null;
    const hasGif = () => Boolean(window.Trevix.gifs && window.Trevix.gifs.hasGif(gifField));
    function clearGif() {
        if (gifField && window.Trevix.gifs) {
            window.Trevix.gifs.clearField(gifField);
        }
    }
    if (gifField) {
        gifField.addEventListener('trevix:gif-change', (event) => {
            if (event.detail.gif) {
                clearAttachment();
                voice.discard();
            }
        });
    }

    /* ---------- Notas de voz ----------
     * Se graba con Web Audio y se codifica como WAV PCM de 16 bits a 16 kHz (mono): suena en cualquier
     * navegador y en la app de iOS sin convertir nada en el servidor, que comprueba formato y duración. */
    const voice = (() => {
        const panel = form ? $('[data-voice-recorder]', form) : null;
        const startButton = form ? $('[data-voice-start]', form) : null;
        const noop = { file: null, discard() {}, recording: false };
        if (!panel || !startButton) {
            return noop;
        }
        const rules = (config.uploads && config.uploads.voice) || { maxSeconds: 120, minSeconds: 1 };
        const label = $('[data-voice-label]', panel);
        const time = $('[data-voice-time]', panel);
        const preview = $('[data-voice-preview]', panel);
        const stopButton = $('[data-voice-stop]', panel);
        const OUT_RATE = 16000;
        const state = { file: null, recording: false };
        let stream = null;
        let ctx = null;
        let node = null;
        let chunks = [];
        let startedAt = 0;
        let ticker = null;

        function clock(seconds) {
            const s = Math.max(0, Math.floor(seconds));
            return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
        }

        function release() {
            window.clearInterval(ticker);
            ticker = null;
            if (node) {
                node.disconnect();
                node.onaudioprocess = null;
                node = null;
            }
            if (stream) {
                stream.getTracks().forEach((track) => track.stop());
                stream = null;
            }
            if (ctx) {
                ctx.close().catch(() => {});
                ctx = null;
            }
            state.recording = false;
        }

        function resetPanel() {
            if (preview.src) {
                URL.revokeObjectURL(preview.src);
            }
            preview.removeAttribute('src');
            preview.hidden = true;
            label.hidden = false;
            label.firstChild.textContent = t('Grabando…') + ' ';
            time.textContent = '0:00';
            stopButton.hidden = false;
            panel.classList.remove('is-ready');
            panel.hidden = true;
        }

        state.discard = () => {
            release();
            chunks = [];
            state.file = null;
            resetPanel();
        };

        function downsample(samples, inRate) {
            if (inRate <= OUT_RATE) {
                return samples;
            }
            const ratio = inRate / OUT_RATE;
            const out = new Float32Array(Math.floor(samples.length / ratio));
            for (let i = 0; i < out.length; i++) {
                const from = Math.floor(i * ratio);
                const to = Math.min(samples.length, Math.floor((i + 1) * ratio));
                let sum = 0;
                for (let j = from; j < to; j++) {
                    sum += samples[j];
                }
                out[i] = to > from ? sum / (to - from) : 0;
            }
            return out;
        }

        function wav(samples, rate) {
            const buffer = new ArrayBuffer(44 + samples.length * 2);
            const view = new DataView(buffer);
            const text = (offset, value) => {
                for (let i = 0; i < value.length; i++) {
                    view.setUint8(offset + i, value.charCodeAt(i));
                }
            };
            text(0, 'RIFF');
            view.setUint32(4, 36 + samples.length * 2, true);
            text(8, 'WAVE');
            text(12, 'fmt ');
            view.setUint32(16, 16, true);
            view.setUint16(20, 1, true);
            view.setUint16(22, 1, true);
            view.setUint32(24, rate, true);
            view.setUint32(28, rate * 2, true);
            view.setUint16(32, 2, true);
            view.setUint16(34, 16, true);
            text(36, 'data');
            view.setUint32(40, samples.length * 2, true);
            for (let i = 0; i < samples.length; i++) {
                const s = Math.max(-1, Math.min(1, samples[i]));
                view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
            }
            return new Blob([buffer], { type: 'audio/wav' });
        }

        function finish() {
            if (!state.recording) {
                return;
            }
            const inRate = ctx ? ctx.sampleRate : OUT_RATE;
            const seconds = (performance.now() - startedAt) / 1000;
            release();
            const total = chunks.reduce((n, c) => n + c.length, 0);
            const merged = new Float32Array(total);
            let offset = 0;
            chunks.forEach((c) => {
                merged.set(c, offset);
                offset += c.length;
            });
            chunks = [];
            if (seconds < Number(rules.minSeconds || 1) || total === 0) {
                state.discard();
                toast(t('La nota de voz es demasiado corta.'), 'error');
                return;
            }
            const blob = wav(downsample(merged, inRate), Math.min(inRate, OUT_RATE));
            state.file = new File([blob], 'nota-de-voz.wav', { type: 'audio/wav' });
            preview.src = URL.createObjectURL(blob);
            preview.hidden = false;
            label.hidden = true;
            stopButton.hidden = true;
            panel.classList.add('is-ready');
        }

        async function start() {
            if (state.recording) {
                return;
            }
            const AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !AudioCtx) {
                toast(t('Tu navegador no permite grabar audio.'), 'error');
                return;
            }
            state.discard();
            try {
                stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
            } catch {
                toast(t('Necesitamos permiso para usar el micrófono. Actívalo en la configuración del navegador.'), 'error');
                return;
            }
            clearAttachment();
            clearGif();
            ctx = new AudioCtx();
            const source = ctx.createMediaStreamSource(stream);
            node = ctx.createScriptProcessor(4096, 1, 1);
            node.onaudioprocess = (event) => {
                chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)));
            };
            source.connect(node);
            node.connect(ctx.destination);
            state.recording = true;
            startedAt = performance.now();
            panel.hidden = false;
            const max = Number(rules.maxSeconds || 120);
            ticker = window.setInterval(() => {
                const elapsed = (performance.now() - startedAt) / 1000;
                time.textContent = clock(elapsed);
                if (elapsed >= max) {
                    finish();
                    toast(t('Llegaste al máximo de {time} por nota de voz.', { time: clock(max) }), 'info');
                }
            }, 250);
        }

        startButton.addEventListener('click', start);
        stopButton.addEventListener('click', finish);
        $('[data-voice-cancel]', panel).addEventListener('click', state.discard);
        return state;
    })();

    /* ---------- Enviar ----------
     * Los mensajes de solo texto aparecen al instante (burbuja «Enviando…») y se envían en orden; la burbuja se
     * reemplaza por la del servidor al confirmarse. Con imagen, nota de voz o GIF se espera la subida. */
    if (form) {
        const input = $('[data-chat-input]', form);
        const submit = $('button[type="submit"]', form);
        const onceToggle = $('[data-voice-once-toggle]', form);
        const draftMode = Boolean($('input[name="to"]', form));
        let sending = false;
        let queue = Promise.resolve();

        input.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
                event.preventDefault();
                form.requestSubmit();
            }
        });

        function setPreview(text) {
            const preview = $('.conv.is-active .conv__preview');
            if (preview && text) {
                preview.textContent = t('Tú: {text}', { text: text.length > 80 ? text.slice(0, 79) + '…' : text });
            }
        }

        function confirmSent(data, pending) {
            const id = String(Number(data.message_id) || '');
            if (id && list.querySelector('[data-message-id="' + id + '"]')) {
                if (pending) {
                    pending.remove();
                }
            } else if (pending) {
                const node = parse(data.html)[0];
                if (node) {
                    pending.replaceWith(node);
                } else {
                    pending.remove();
                }
            } else {
                append(data.html);
            }
            lastId = Math.max(lastId, Number(data.message_id) || 0);
            if (!firstId) {
                firstId = lastId;
            }
            updateSeen();
        }

        function pendingBubble(text) {
            const row = document.createElement('div');
            row.className = 'bubble-row bubble-row--mine is-pending';
            const bubble = document.createElement('p');
            bubble.className = 'bubble';
            bubble.textContent = text;
            const meta = document.createElement('span');
            meta.className = 'bubble__meta';
            meta.textContent = t('Enviando…');
            row.append(bubble, meta);
            list.appendChild(row);
            toBottom();
            return row;
        }

        function failBubble(row, text, message) {
            row.classList.remove('is-pending');
            row.classList.add('is-failed');
            const meta = $('.bubble__meta', row);
            meta.textContent = message + ' · ';
            const retry = document.createElement('button');
            retry.type = 'button';
            retry.className = 'bubble__retry';
            retry.textContent = t('Reintentar');
            retry.addEventListener('click', () => {
                row.remove();
                input.value = input.value.trim() !== '' ? input.value : text;
                form.requestSubmit();
            });
            meta.appendChild(retry);
        }

        form.addEventListener('submit', async (event) => {
            event.preventDefault();
            if (sending) {
                return;
            }
            if (voice.recording) {
                toast(t('Detén la grabación antes de enviar la nota de voz.'), 'info');
                return;
            }
            const hasFile = fileInput && fileInput.files && fileInput.files.length > 0;
            const withGif = hasGif();
            const withVoice = Boolean(voice.file);
            const text = input.value.trim();
            if (text === '' && !hasFile && !withGif && !withVoice) {
                input.focus();
                return;
            }
            const payload = new FormData(form);
            if (withVoice) {
                payload.set('voice', voice.file, voice.file.name);
            } else {
                payload.delete('view_once');
            }

            if (!draftMode && !hasFile && !withGif && !withVoice) {
                const pending = pendingBubble(text);
                setPreview(text.replace(/\s+/g, ' '));
                input.value = '';
                input.style.height = '';
                input.focus();
                queue = queue.then(async () => {
                    try {
                        confirmSent(await postForm(form, payload), pending);
                    } catch (error) {
                        failBubble(pending, text, error.message);
                    }
                });
                return;
            }

            sending = true;
            submit.disabled = true;
            form.classList.add('is-busy');
            try {
                await queue;
                const data = await postForm(form, payload);
                if (draftMode) {
                    window.location.href = data.url;
                    return;
                }
                confirmSent(data, null);
                setPreview(text.replace(/\s+/g, ' ') || (withVoice ? t('Nota de voz') : (withGif ? 'GIF' : t('Foto'))));
                input.value = '';
                input.style.height = '';
                clearAttachment();
                clearGif();
                voice.discard();
                if (onceToggle) {
                    onceToggle.checked = false;
                }
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

    /* ---------- Reacciones ----------
     * El botón de cada mensaje abre la barra con tus reacciones rápidas; doble clic en un mensaje reacciona con la
     * primera (por defecto 🖤). Volver a elegir la misma la quita. */
    let quick = [];
    try {
        quick = JSON.parse(scroller.getAttribute('data-quick-reactions') || '[]');
    } catch {
        quick = [];
    }
    const csrf = form ? $('input[name="_csrf"]', form) : $('input[name="_csrf"]');
    let bar = null;

    async function react(row, emoji) {
        const id = row.getAttribute('data-message-id');
        const opener = $('[data-react-open]', row);
        const current = opener ? opener.dataset.myReaction : '';
        const data = new FormData();
        data.append('_csrf', csrf ? csrf.value : (config.csrfToken || ''));
        data.append('action', 'react');
        data.append('message_id', id);
        data.append('emoji', current === emoji ? '' : emoji);
        try {
            const result = await window.Trevix.api('api/messages.php', { method: 'POST', data });
            const node = parse(result.html)[0];
            if (node) {
                row.replaceWith(node);
            }
        } catch (error) {
            toast(error.message, 'error');
        }
    }

    function closeBar() {
        if (bar) {
            bar.remove();
            bar = null;
        }
    }

    function openBar(button) {
        closeBar();
        const row = button.closest('[data-message-id]');
        bar = document.createElement('div');
        bar.className = 'react-bar';
        bar.setAttribute('role', 'toolbar');
        bar.setAttribute('aria-label', t('Reaccionar'));
        quick.forEach((emoji) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = 'react-bar__emoji' + (button.dataset.myReaction === emoji ? ' is-mine' : '');
            b.textContent = emoji;
            b.addEventListener('click', () => {
                closeBar();
                react(row, emoji);
            });
            bar.appendChild(b);
        });
        const edit = document.createElement('button');
        edit.type = 'button';
        edit.className = 'react-bar__edit';
        edit.textContent = '+';
        edit.setAttribute('aria-label', t('Personalizar reacciones rápidas'));
        edit.addEventListener('click', () => {
            closeBar();
            openQuickDialog();
        });
        bar.appendChild(edit);
        row.appendChild(bar);
        const first = $('button', bar);
        if (first) {
            first.focus();
        }
    }

    list.addEventListener('click', (event) => {
        const open = event.target.closest('[data-react-open]');
        if (open) {
            event.preventDefault();
            if (bar && bar.parentElement === open.closest('[data-message-id]')) {
                closeBar();
            } else {
                openBar(open);
            }
        }
    });
    list.addEventListener('dblclick', (event) => {
        const row = event.target.closest('[data-message-id]');
        if (!row || !quick.length || !$('[data-react-open]', row) || event.target.closest('a, button, audio, video, form')) {
            return;
        }
        window.getSelection()?.removeAllRanges();
        react(row, quick[0]);
    });
    document.addEventListener('click', (event) => {
        if (bar && !event.target.closest('.react-bar') && !event.target.closest('[data-react-open]')) {
            closeBar();
        }
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            closeBar();
        }
    });

    /* ---------- Personalizar reacciones rápidas ---------- */
    const quickDialog = $('#quick-reactions');
    function openQuickDialog() {
        if (quickDialog && typeof quickDialog.showModal === 'function') {
            quickDialog.showModal();
        }
    }
    document.addEventListener('click', (event) => {
        if (event.target.closest('[data-quick-reactions-open]')) {
            window.Trevix.closeDropdowns && window.Trevix.closeDropdowns();
            openQuickDialog();
        }
    });
    if (quickDialog) {
        const slots = $$('[data-quick-slot]', quickDialog);
        $$('[data-quick-pick]', quickDialog).forEach((pick) => pick.addEventListener('click', () => {
            const emoji = pick.getAttribute('data-quick-pick');
            if (slots.some((s) => s.value.trim() === emoji)) {
                return;
            }
            const free = slots.find((s) => s.value.trim() === '');
            if (free) {
                free.value = emoji;
            } else {
                toast(t('Vacía un espacio para añadir otro emoji.'), 'info');
            }
        }));
        const reset = $('[data-quick-reset]', quickDialog);
        if (reset) {
            reset.addEventListener('click', () => {
                let defaults = [];
                try {
                    defaults = JSON.parse(reset.getAttribute('data-quick-reset') || '[]');
                } catch {
                    defaults = [];
                }
                slots.forEach((s, i) => {
                    s.value = defaults[i] || '';
                });
            });
        }
        const quickForm = $('[data-quick-reactions-form]', quickDialog);
        quickForm.addEventListener('submit', async (event) => {
            event.preventDefault();
            try {
                const data = await postForm(quickForm);
                quick = data.reactions || quick;
                scroller.setAttribute('data-quick-reactions', JSON.stringify(quick));
                slots.forEach((s, i) => {
                    s.value = quick[i] || '';
                });
                quickDialog.close();
                toast(data.message || t('Guardaste tus reacciones rápidas.'), 'success');
            } catch (error) {
                toast(error.message, 'error');
            }
        });
    }

    /* ---------- Nota de voz de una sola vez ----------
     * Se descarga una única vez (el servidor la marca como escuchada al entregarla) y se reproduce desde memoria. */
    list.addEventListener('click', async (event) => {
        const play = event.target.closest('[data-voice-once-play]');
        if (!play || play.dataset.loading) {
            return;
        }
        const ok = await confirmAction(t('Esta nota de voz solo se puede escuchar una vez. ¿Escucharla ahora?'), t('Escuchar'));
        if (!ok) {
            return;
        }
        play.dataset.loading = '1';
        play.disabled = true;
        const holder = play.closest('[data-voice-once]');
        try {
            const response = await fetch(play.getAttribute('data-url'), { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } });
            if (!response.ok) {
                const payload = await response.json().catch(() => ({}));
                throw new Error(payload.error || t('No se pudo abrir la nota de voz.'));
            }
            const blobUrl = URL.createObjectURL(await response.blob());
            const audio = document.createElement('audio');
            audio.controls = true;
            audio.autoplay = true;
            audio.src = blobUrl;
            audio.className = 'voice-once__audio';
            audio.addEventListener('ended', () => {
                URL.revokeObjectURL(blobUrl);
                const label = document.createElement('span');
                label.textContent = t('Nota de voz de una sola vez') + ' · ' + t('Escuchada');
                audio.replaceWith(label);
                holder.classList.add('is-opened');
            });
            play.replaceWith(audio);
        } catch (error) {
            play.disabled = false;
            delete play.dataset.loading;
            toast(error.message, 'error');
        }
    });

    /* ---------- Eliminar mensaje propio ---------- */
    document.addEventListener('submit', async (event) => {
        const deleteForm = event.target.closest('[data-message-delete]');
        if (!deleteForm) {
            return;
        }
        event.preventDefault();
        const ok = await confirmAction(t('¿Eliminar este mensaje? En la conversación quedará la marca «Mensaje eliminado».'), t('Eliminar'));
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
        link.textContent = t('Cargando…');
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
            toast(t('No se pudieron cargar los mensajes anteriores.'), 'error');
        }
    });

    /* ---------- Inicio ---------- */
    if (!window.location.search.includes('before=')) {
        toBottom();
    }
    updateSeen();
    start();
});
