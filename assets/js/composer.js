/*
 * TREVIX · Compositor de publicaciones
 * Gestiona el modal de creación: formato (publicación o hilo), contador de caracteres
 * y adjuntos con la misma validación de tipo, extensión y tamaño que aplicará el servidor.
 */
(function () {
    'use strict';

    const { $, $$, config, formatBytes } = window.Trevix;
    const dialog = $('#composer');
    if (!dialog) {
        return;
    }

    const form = $('[data-composer-form]', dialog);
    const textarea = $('[data-composer-text]', dialog);
    const counter = $('[data-char-counter]', dialog);
    const mediaList = $('[data-composer-media]', dialog);
    const errorBox = $('[data-composer-error]', dialog);
    const hiddenInput = $('[data-composer-files]', dialog);
    const title = $('#composer-title', dialog);
    const template = document.getElementById('tpl-media-item');
    const songField = $('[data-song-field]', dialog);
    const music = () => window.Trevix.music;

    const uploads = config.uploads || { maxFiles: 10, image: { mimes: [], maxBytes: 0 }, video: { mimes: [], maxBytes: 0 } };
    const maxBody = Number(textarea.getAttribute('maxlength')) || 2000;
    const EXTENSIONS = {
        image: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        video: ['mp4', 'webm', 'mov'],
    };

    /** @type {{file: File, url: string, kind: 'image'|'video'}[]} */
    let attachments = [];

    function setFormat(format) {
        const radio = $('[data-composer-format-input][value="' + format + '"]', dialog);
        if (radio) {
            radio.checked = true;
        }
        dialog.dataset.format = format;
        title.textContent = format === 'thread' ? 'Nuevo hilo' : 'Crear publicación';
        textarea.placeholder = textarea.getAttribute('data-placeholder-' + format) || '';
        const swatches = $('[data-composer-backgrounds]', dialog);
        if (swatches) {
            swatches.hidden = format !== 'thread';
            swatches.disabled = format !== 'thread';
        }
        paintBackground();
    }

    /** Vista previa del fondo de color del hilo en el propio cuadro de texto. */
    function paintBackground() {
        const checked = $('[data-composer-backgrounds] input[name="background"]:checked', dialog);
        const value = dialog.dataset.format === 'thread' && checked ? checked.value : '';
        Array.from(textarea.classList).filter((c) => c.startsWith('story-bg--')).forEach((c) => textarea.classList.remove(c));
        if (value) {
            textarea.classList.add('story-bg--' + value);
        }
        dialog.classList.toggle('has-background', value !== '');
    }

    function updateCounter() {
        const remaining = maxBody - textarea.value.length;
        counter.textContent = String(remaining);
        counter.classList.toggle('is-warning', remaining <= 100 && remaining > 20);
        counter.classList.toggle('is-danger', remaining <= 20);
    }

    function showError(message) {
        errorBox.textContent = message;
        errorBox.hidden = !message;
    }

    function kindOf(file) {
        const extension = (file.name.split('.').pop() || '').toLowerCase();
        if (uploads.image.mimes.includes(file.type) && EXTENSIONS.image.includes(extension)) {
            return 'image';
        }
        if (uploads.video.mimes.includes(file.type) && EXTENSIONS.video.includes(extension)) {
            return 'video';
        }
        return null;
    }

    function syncHiddenInput() {
        try {
            const transfer = new DataTransfer();
            attachments.forEach((item) => transfer.items.add(item.file));
            hiddenInput.files = transfer.files;
        } catch {
            /* Navegadores sin DataTransfer construible: el envío con JavaScript arma su propio FormData. */
        }
    }

    function renderAttachments() {
        mediaList.replaceChildren();
        attachments.forEach((item, index) => {
            const li = template.content.firstElementChild.cloneNode(true);
            const media = document.createElement(item.kind === 'video' ? 'video' : 'img');
            media.src = item.url;
            if (item.kind === 'video') {
                media.muted = true;
                media.playsInline = true;
                media.preload = 'metadata';
            } else {
                media.alt = item.file.name;
            }
            const tag = document.createElement('span');
            tag.className = 'composer__media-tag';
            tag.textContent = (item.kind === 'video' ? 'Video · ' : '') + formatBytes(item.file.size);
            li.prepend(media);
            li.appendChild(tag);
            li.querySelector('.composer__media-remove').addEventListener('click', () => removeAttachment(index));
            mediaList.appendChild(li);
        });
        mediaList.hidden = attachments.length === 0;
        syncHiddenInput();
    }

    function removeAttachment(index) {
        const [removed] = attachments.splice(index, 1);
        if (removed) {
            URL.revokeObjectURL(removed.url);
        }
        showError('');
        renderAttachments();
    }

    function addFiles(fileList) {
        if (dialog.classList.contains('is-sharing')) {
            showError('Al compartir una publicación no se pueden adjuntar archivos.');
            return;
        }
        if (dialog.classList.contains('has-event')) {
            showError('Un evento lleva solo su portada: quita el evento para adjuntar fotos o videos.');
            return;
        }
        if (dialog.classList.contains('has-background')) {
            showError('Un hilo con fondo de color no lleva fotos ni videos.');
            return;
        }
        const gifPicked = $('[data-gif-field] [data-gif-id]', dialog);
        if (gifPicked && gifPicked.value !== '') {
            showError('Un GIF se publica sin fotos ni videos: quita el GIF para adjuntar archivos.');
            return;
        }
        const errors = [];
        Array.from(fileList).forEach((file) => {
            const kind = kindOf(file);
            if (!kind) {
                errors.push('“' + file.name + '” no es un formato permitido.');
                return;
            }
            const limit = uploads[kind].maxBytes;
            if (file.size > limit) {
                errors.push('“' + file.name + '” supera el máximo de ' + formatBytes(limit) + '.');
                return;
            }
            if (attachments.length >= uploads.maxFiles) {
                errors.push('Puedes adjuntar hasta ' + uploads.maxFiles + ' archivos por publicación.');
                return;
            }
            if (kind === 'video' && attachments.some((item) => item.kind === 'video')) {
                errors.push('Solo se permite un video por publicación.');
                return;
            }
            attachments.push({ file, url: URL.createObjectURL(file), kind });
        });
        showError(Array.from(new Set(errors)).join(' '));
        renderAttachments();
    }

    /* ---------- Compartir otra publicación ---------- */
    const shareBox = $('[data-composer-share]', dialog);
    const shareId = $('[data-composer-share-id]', dialog);

    function setShare(share) {
        const active = Boolean(share && share.id);
        shareBox.hidden = !active;
        shareId.disabled = !active;
        shareId.value = active ? share.id : '';
        dialog.classList.toggle('is-sharing', active);
        if (active) {
            $('[data-composer-share-author]', dialog).textContent = share.author || '';
            const text = $('[data-composer-share-text]', dialog);
            text.textContent = share.text || '';
            text.hidden = !share.text;
            attachments.forEach((item) => URL.revokeObjectURL(item.url));
            attachments = [];
            renderAttachments();
            if (songField && music()) {
                music().clearField(songField);
            }
            if (gifField && gifs()) {
                gifs().clearField(gifField);
            }
            setPanel('event', false);
            setFormat('post');
            title.textContent = 'Compartir publicación';
            textarea.placeholder = 'Agrega un comentario (opcional)';
        }
    }

    /* ---------- Publicar dentro de una comunidad ---------- */
    const communityBox = $('[data-composer-community]', dialog);
    const communityId = $('[data-composer-community-id]', dialog);
    const visibilitySelect = $('#composer-visibility', dialog);

    /** En una comunidad la visibilidad la decide la comunidad: se fija en "Público" y se bloquea. */
    function setCommunity(community) {
        const active = Boolean(community && community.id);
        communityBox.hidden = !active;
        communityId.disabled = !active;
        communityId.value = active ? community.id : '';
        visibilitySelect.disabled = active;
        if (active) {
            visibilitySelect.value = 'public';
            $('[data-composer-community-name]', dialog).textContent = community.name || '';
        }
    }

    /* ---------- Ubicación, acontecimiento, evento y fondo del hilo ---------- */
    const backgrounds = $('[data-composer-backgrounds]', dialog);
    const gifField = $('[data-gif-field]', dialog);
    const gifs = () => window.Trevix.gifs;
    const hasGif = () => Boolean(gifField && gifs() && gifs().hasGif(gifField));
    const panel = (name) => $('[data-composer-panel="' + name + '"]', dialog);
    const panelOpen = (name) => {
        const el = panel(name);
        return Boolean(el && !el.hidden);
    };
    const coverInput = $('[data-composer-event-cover]', dialog);
    const coverPreview = $('[data-composer-event-preview]', dialog);
    let coverUrl = null;

    function clearCover() {
        if (coverUrl) {
            URL.revokeObjectURL(coverUrl);
            coverUrl = null;
        }
        if (coverPreview) {
            coverPreview.hidden = true;
            coverPreview.removeAttribute('src');
        }
    }

    function setPanel(name, open) {
        const el = panel(name);
        if (!el) {
            return;
        }
        if (open && name === 'event' && (attachments.length > 0 || hasGif() || !shareId.disabled)) {
            showError('Un evento se publica con su portada, sin otros archivos ni GIF.');
            return;
        }
        el.hidden = !open;
        el.disabled = !open;
        if (!open) {
            $$('input:not([type="radio"]), textarea, select', el).forEach((input) => {
                input.value = '';
            });
            if (name === 'event') {
                clearCover();
            }
        } else {
            showError('');
            const first = $('input:not([type="hidden"]):not([type="file"]), select', el);
            if (first) {
                first.focus();
            }
        }
        dialog.classList.toggle('has-event', panelOpen('event'));
    }

    function hasBackground() {
        const checked = $('input[name="background"]:checked', dialog);
        return Boolean(checked && checked.value && dialog.dataset.format === 'thread');
    }

    $$('[data-composer-tool]', dialog).forEach((button) => {
        button.addEventListener('click', () => {
            const name = button.getAttribute('data-composer-tool');
            setPanel(name, !panelOpen(name));
        });
    });
    $$('[data-composer-panel-close]', dialog).forEach((button) => {
        button.addEventListener('click', () => setPanel(button.closest('[data-composer-panel]').getAttribute('data-composer-panel'), false));
    });

    if (coverInput) {
        coverInput.addEventListener('change', () => {
            clearCover();
            const file = coverInput.files && coverInput.files[0];
            if (!file) {
                return;
            }
            if (!uploads.image.mimes.includes(file.type)) {
                showError('La portada debe ser una imagen JPG, PNG o WEBP.');
                coverInput.value = '';
                return;
            }
            coverUrl = URL.createObjectURL(file);
            coverPreview.src = coverUrl;
            coverPreview.hidden = false;
        });
    }

    const locateButton = $('[data-composer-locate]', dialog);
    if (locateButton) {
        locateButton.addEventListener('click', () => {
            if (!navigator.geolocation) {
                showError('Tu navegador no permite obtener la ubicación. Escribe el lugar.');
                return;
            }
            locateButton.disabled = true;
            navigator.geolocation.getCurrentPosition(async (position) => {
                const lat = position.coords.latitude.toFixed(3);
                const lng = position.coords.longitude.toFixed(3);
                try {
                    const place = await window.Trevix.api('api/geo.php?lat=' + lat + '&lng=' + lng);
                    $('[data-composer-place]', dialog).value = place.name;
                    $('[data-composer-lat]', dialog).value = String(place.lat);
                    $('[data-composer-lng]', dialog).value = String(place.lng);
                    showError('');
                } catch (error) {
                    showError(error.message);
                } finally {
                    locateButton.disabled = false;
                }
            }, (error) => {
                locateButton.disabled = false;
                showError(error.code === 1
                    ? 'No diste permiso para usar tu ubicación. Puedes escribir el lugar.'
                    : 'No se pudo obtener tu ubicación. Escribe el lugar.');
            }, { enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 });
        });
    }
    /* Si se escribe otro lugar a mano, ya no corresponde a las coordenadas detectadas. */
    const placeInput = $('[data-composer-place]', dialog);
    if (placeInput) {
        placeInput.addEventListener('input', () => {
            $('[data-composer-lat]', dialog).value = '';
            $('[data-composer-lng]', dialog).value = '';
        });
    }

    if (backgrounds) {
        backgrounds.addEventListener('change', () => {
            paintBackground();
            if (hasBackground() && attachments.length > 0) {
                showError('Un hilo con fondo de color no lleva fotos ni videos: quita los archivos o el fondo.');
            }
        });
    }

    if (gifField) {
        gifField.addEventListener('trevix:gif-change', (event) => {
            if (event.detail.gif && panelOpen('event')) {
                setPanel('event', false);
            }
        });
    }

    /* ---------- Sugerencias de @menciones ---------- */
    const mentionList = $('[data-mention-list]', dialog);
    let mentionTimer = null;
    let mentionRequest = 0;
    let mentionIndex = -1;

    function mentionQuery() {
        const before = textarea.value.slice(0, textarea.selectionStart);
        const match = before.match(/(^|\s)@([\p{L}\p{N}._]{1,30})$/u);
        return match ? match[2] : null;
    }

    function hideMentions() {
        if (!mentionList) {
            return;
        }
        mentionList.hidden = true;
        mentionList.replaceChildren();
        mentionIndex = -1;
    }

    function insertMention(username) {
        const caret = textarea.selectionStart;
        const before = textarea.value.slice(0, caret).replace(/@([\p{L}\p{N}._]{1,30})$/u, '@' + username + ' ');
        textarea.value = before + textarea.value.slice(caret);
        textarea.setSelectionRange(before.length, before.length);
        hideMentions();
        updateCounter();
        textarea.focus();
    }

    function highlightMention(index) {
        const items = $$('[role="option"]', mentionList);
        mentionIndex = items.length ? (index + items.length) % items.length : -1;
        items.forEach((item, i) => item.setAttribute('aria-selected', i === mentionIndex ? 'true' : 'false'));
    }

    async function suggestMentions() {
        const query = mentionQuery();
        if (!query) {
            hideMentions();
            return;
        }
        const id = ++mentionRequest;
        try {
            const data = await window.Trevix.api('api/mentions.php?q=' + encodeURIComponent(query));
            if (id !== mentionRequest || mentionQuery() !== query) {
                return;
            }
            mentionList.replaceChildren();
            data.items.forEach((user) => {
                const li = document.createElement('li');
                li.setAttribute('role', 'option');
                li.className = 'mention-suggest__item';
                if (user.avatar) {
                    const img = document.createElement('img');
                    img.src = user.avatar;
                    img.alt = '';
                    li.appendChild(img);
                }
                const name = document.createElement('strong');
                name.textContent = user.display_name;
                const handle = document.createElement('span');
                handle.textContent = '@' + user.username;
                li.append(name, handle);
                li.addEventListener('mousedown', (event) => {
                    event.preventDefault();
                    insertMention(user.username);
                });
                li.dataset.username = user.username;
                mentionList.appendChild(li);
            });
            mentionList.hidden = data.items.length === 0;
            highlightMention(0);
        } catch {
            hideMentions();
        }
    }

    if (mentionList) {
        textarea.addEventListener('input', () => {
            window.clearTimeout(mentionTimer);
            mentionTimer = window.setTimeout(suggestMentions, 220);
        });
        textarea.addEventListener('keydown', (event) => {
            if (mentionList.hidden) {
                return;
            }
            if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                event.preventDefault();
                highlightMention(mentionIndex + (event.key === 'ArrowDown' ? 1 : -1));
            } else if (event.key === 'Enter' || event.key === 'Tab') {
                const item = $$('[role="option"]', mentionList)[mentionIndex];
                if (item) {
                    event.preventDefault();
                    insertMention(item.dataset.username);
                }
            } else if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                hideMentions();
            }
        });
        textarea.addEventListener('blur', () => window.setTimeout(hideMentions, 150));
    }

    $('[data-composer-share-cancel]', dialog).addEventListener('click', () => {
        setShare(null);
        setFormat('post');
        textarea.focus();
    });

    /* ---------- Envío ---------- */
    const submitButton = $('[data-composer-submit]', dialog);
    const progress = $('[data-composer-progress]', dialog);
    const progressBar = $('[data-composer-progress-bar]', dialog);
    let sending = false;

    function resetComposer() {
        form.reset();
        attachments.forEach((item) => URL.revokeObjectURL(item.url));
        attachments = [];
        renderAttachments();
        if (songField && music()) {
            music().clearField(songField);
        }
        setShare(null);
        setCommunity(null);
        ['life', 'location', 'event'].forEach((name) => setPanel(name, false));
        hideMentions();
        setFormat('post');
        updateCounter();
        showError('');
        textarea.style.height = '';
    }

    function setSending(state) {
        sending = state;
        submitButton.disabled = state;
        submitButton.textContent = state ? 'Publicando…' : 'Publicar';
        progress.hidden = !state;
        progressBar.style.width = '0%';
    }

    /** Inserta la nueva tarjeta en el feed visible si corresponde; si no, abre la publicación. */
    function placeNewPost(payload) {
        const feed = document.querySelector('[data-feed-live]');
        const accepts = feed ? (feed.getAttribute('data-feed-live') || '').split(' ') : [];
        const feedCommunity = feed ? feed.getAttribute('data-feed-community') : null;
        const otherCommunity = feedCommunity !== null && String(payload.community_id || '') !== feedCommunity;
        if (!feed || !payload.html || !accepts.includes(payload.format) || otherCommunity) {
            window.location.href = payload.url;
            return;
        }
        $$('.empty-state', feed).forEach((el) => el.remove());
        const holder = document.createElement('div');
        holder.innerHTML = payload.html;
        const card = holder.firstElementChild;
        feed.prepend(card);
        if (window.Trevix.enhancePosts) {
            window.Trevix.enhancePosts(card);
        }
        card.classList.add('is-new');
    }

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        if (sending) {
            return;
        }
        const text = textarea.value.trim();
        const isThread = dialog.dataset.format === 'thread';
        if (isThread && text === '') {
            showError('Escribe el texto del hilo.');
            return;
        }
        const withSong = Boolean(songField && music() && music().hasSong(songField));
        const lifeSelect = $('[data-composer-life]', dialog);
        const withExtra = hasGif() || panelOpen('event') || (panelOpen('life') && lifeSelect && lifeSelect.value !== '');
        if (text === '' && attachments.length === 0 && shareId.disabled && !withSong && !withExtra) {
            showError('Escribe algo o adjunta una imagen, un video, un GIF o una canción.');
            return;
        }
        if (panelOpen('event')) {
            const missing = $$('[required]', panel('event')).find((input) => input.value.trim() === '');
            if (missing) {
                showError('Completa el nombre, la fecha de inicio y el lugar del evento.');
                missing.focus();
                return;
            }
        }
        if (hasBackground() && attachments.length > 0) {
            showError('Un hilo con fondo de color no lleva fotos ni videos.');
            return;
        }
        if (textarea.value.length > maxBody) {
            showError('El texto no puede superar los ' + maxBody + ' caracteres.');
            return;
        }
        showError('');

        const data = new FormData(form);
        data.delete('media[]');
        attachments.forEach((item) => data.append('media[]', item.file, item.file.name));

        const xhr = new XMLHttpRequest();
        xhr.open('POST', form.getAttribute('action'));
        xhr.setRequestHeader('Accept', 'application/json');
        xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
        xhr.setRequestHeader('X-CSRF-Token', config.csrfToken || '');
        xhr.responseType = 'json';

        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                progressBar.style.width = Math.round((e.loaded / e.total) * 100) + '%';
            }
        });
        xhr.addEventListener('load', () => {
            setSending(false);
            const payload = xhr.response || {};
            if (xhr.status >= 200 && xhr.status < 300 && payload.ok) {
                const wasShare = !shareId.disabled;
                resetComposer();
                dialog.close();
                window.Trevix.toast(wasShare ? 'Compartiste la publicación' : 'Publicación creada', 'success');
                placeNewPost(payload);
                return;
            }
            if (xhr.status === 401) {
                window.location.href = (config.baseUrl || '') + '/login.php';
                return;
            }
            showError(payload.error || (xhr.status === 413
                ? 'Los archivos superan el tamaño que acepta el servidor.'
                : 'No se pudo publicar. Inténtalo de nuevo.'));
        });
        xhr.addEventListener('error', () => {
            setSending(false);
            showError('Sin conexión con el servidor. Revisa tu red e inténtalo de nuevo.');
        });

        setSending(true);
        xhr.send(data);
    });

    dialog.addEventListener('cancel', (event) => {
        if (sending) {
            event.preventDefault();
        }
    });

    function open(options = {}) {
        if (!options.share && !shareId.disabled) {
            setShare(null);
        }
        setCommunity(options.share ? null : options.community);
        setFormat(options.format || dialog.dataset.format || 'post');
        if (options.share) {
            setShare(options.share);
        }
        if (!dialog.open) {
            dialog.showModal();
        }
        if (options.panel) {
            setPanel(options.panel, true);
        } else if (options.song && songField && music() && music().choose) {
            music().choose(songField, options.song);
        } else if (options.pick) {
            const picker = $('[data-composer-pick-input="' + options.pick + '"]', dialog);
            if (picker) {
                picker.click();
            }
        } else {
            textarea.focus();
        }
    }

    function songFromTrigger(trigger) {
        const raw = trigger.getAttribute('data-composer-song');
        if (!raw) {
            return null;
        }
        try {
            return JSON.parse(raw);
        } catch {
            return null;
        }
    }

    document.addEventListener('click', (event) => {
        const shareTrigger = event.target.closest('[data-share-post]');
        if (shareTrigger && !shareTrigger.disabled) {
            open({
                share: {
                    id: shareTrigger.getAttribute('data-share-post'),
                    author: shareTrigger.getAttribute('data-share-author'),
                    text: shareTrigger.getAttribute('data-share-text'),
                },
            });
            return;
        }
        const trigger = event.target.closest('[data-open-composer]');
        if (!trigger) {
            return;
        }
        open({
            format: trigger.getAttribute('data-composer-format') || undefined,
            pick: trigger.getAttribute('data-composer-pick') || undefined,
            panel: trigger.getAttribute('data-composer-panel') || undefined,
            song: songFromTrigger(trigger),
            community: trigger.hasAttribute('data-composer-community')
                ? { id: trigger.getAttribute('data-composer-community'), name: trigger.getAttribute('data-composer-community-name') }
                : null,
        });
    });

    $$('[data-composer-format-input]', dialog).forEach((radio) => {
        radio.addEventListener('change', () => setFormat(radio.value));
    });

    $$('[data-composer-pick-input]', dialog).forEach((input) => {
        input.addEventListener('change', () => {
            if (input.files && input.files.length) {
                addFiles(input.files);
            }
            input.value = '';
        });
    });

    textarea.addEventListener('input', updateCounter);

    form.addEventListener('dragover', (event) => {
        event.preventDefault();
    });
    form.addEventListener('drop', (event) => {
        event.preventDefault();
        if (event.dataTransfer && event.dataTransfer.files.length) {
            addFiles(event.dataTransfer.files);
        }
    });

    setFormat('post');
    updateCounter();
})();
