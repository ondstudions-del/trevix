/*
 * TREVIX · Mensajes privados
 * Envía sin recargar (texto con imagen, nota de voz o GIF), consulta mensajes nuevos cada pocos segundos mientras la
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
            label.firstChild.textContent = 'Grabando… ';
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
                toast('La nota de voz es demasiado corta.', 'error');
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
                toast('Tu navegador no permite grabar audio.', 'error');
                return;
            }
            state.discard();
            try {
                stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
            } catch {
                toast('Necesitamos permiso para usar el micrófono. Actívalo en la configuración del navegador.', 'error');
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
                    toast('Llegaste al máximo de ' + clock(max) + ' por nota de voz.', 'info');
                }
            }, 250);
        }

        startButton.addEventListener('click', start);
        stopButton.addEventListener('click', finish);
        $('[data-voice-cancel]', panel).addEventListener('click', state.discard);
        return state;
    })();

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
            if (voice.recording) {
                toast('Detén la grabación antes de enviar la nota de voz.', 'info');
                return;
            }
            const hasFile = fileInput && fileInput.files && fileInput.files.length > 0;
            const withGif = hasGif();
            const withVoice = Boolean(voice.file);
            if (input.value.trim() === '' && !hasFile && !withGif && !withVoice) {
                input.focus();
                return;
            }
            sending = true;
            submit.disabled = true;
            form.classList.add('is-busy');
            try {
                const payload = new FormData(form);
                if (withVoice) {
                    payload.set('voice', voice.file, voice.file.name);
                }
                const data = await postForm(form, payload);
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
                    const text = input.value.trim().replace(/\s+/g, ' ') || (withVoice ? 'Nota de voz' : (withGif ? 'GIF' : 'Foto'));
                    preview.textContent = 'Tú: ' + (text.length > 80 ? text.slice(0, 79) + '…' : text);
                }
                input.value = '';
                input.style.height = '';
                clearAttachment();
                clearGif();
                voice.discard();
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
