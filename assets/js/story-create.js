/*
 * TREVIX · Crear historia
 * Vista previa del archivo o del texto, misma validación que el servidor (tipo, tamaño y duración
 * del video) y envío con barra de progreso. Sin JavaScript el formulario se envía igual.
 */
(function () {
    'use strict';

    const form = document.querySelector('[data-story-create]');
    if (!form) {
        return;
    }
    const { config, t } = window.Trevix;
    const fileInput = form.querySelector('[data-story-file]');
    const preview = form.querySelector('[data-story-preview]');
    const drop = form.querySelector('[data-story-drop]');
    const textPanel = form.querySelector('[data-story-text-panel]');
    const textArea = form.querySelector('[data-story-text]');
    const errorBox = form.querySelector('[data-story-error]');
    const submit = form.querySelector('[data-story-submit]');
    const progress = form.querySelector('[data-story-progress]');
    const progressBar = form.querySelector('[data-story-progress-bar]');

    const uploads = config.uploads || { image: { mimes: [] }, video: { mimes: [] } };
    const maxSeconds = Number(form.getAttribute('data-video-seconds')) || 30;
    const maxVideo = Number(form.getAttribute('data-video-bytes')) || 0;
    const maxImage = Number(form.getAttribute('data-image-bytes')) || 0;
    let objectUrl = null;
    let sending = false;

    const type = () => (form.querySelector('[data-story-type]:checked') || {}).value || 'media';
    const formatBytes = window.Trevix.formatBytes;

    function showError(message) {
        errorBox.textContent = message;
        errorBox.hidden = !message;
    }

    function clearFile() {
        if (objectUrl) {
            URL.revokeObjectURL(objectUrl);
            objectUrl = null;
        }
        fileInput.value = '';
        preview.replaceChildren();
        preview.hidden = true;
        drop.hidden = false;
    }

    function videoDuration(url) {
        return new Promise((resolve) => {
            const probe = document.createElement('video');
            probe.preload = 'metadata';
            probe.onloadedmetadata = () => resolve(probe.duration);
            probe.onerror = () => resolve(NaN);
            probe.src = url;
        });
    }

    async function onFile() {
        showError('');
        const file = fileInput.files && fileInput.files[0];
        if (objectUrl) {
            URL.revokeObjectURL(objectUrl);
            objectUrl = null;
        }
        preview.replaceChildren();
        if (!file) {
            clearFile();
            return;
        }
        const isImage = uploads.image.mimes.includes(file.type);
        const isVideo = uploads.video.mimes.includes(file.type);
        if (!isImage && !isVideo) {
            clearFile();
            showError(t('Formato no permitido. Usa JPG, PNG, WEBP, GIF, MP4, WEBM o MOV.'));
            return;
        }
        const limit = isVideo ? maxVideo : maxImage;
        if (limit && file.size > limit) {
            clearFile();
            showError(isVideo
                ? t('El video puede pesar como máximo {size}.', { size: formatBytes(limit) })
                : t('La imagen puede pesar como máximo {size}.', { size: formatBytes(limit) }));
            return;
        }
        objectUrl = URL.createObjectURL(file);
        if (isVideo) {
            const seconds = await videoDuration(objectUrl);
            if (Number.isFinite(seconds) && seconds > maxSeconds + 0.5) {
                clearFile();
                showError(t('El video dura {seconds} s. Las historias admiten hasta {max} s.', { seconds: Math.round(seconds), max: maxSeconds }));
                return;
            }
        }
        const media = document.createElement(isVideo ? 'video' : 'img');
        media.src = objectUrl;
        if (isVideo) {
            media.muted = true;
            media.loop = true;
            media.autoplay = true;
            media.playsInline = true;
        } else {
            media.alt = t('Vista previa');
        }
        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'icon-btn icon-btn--sm story-create__remove';
        remove.setAttribute('aria-label', t('Quitar archivo'));
        remove.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>';
        remove.addEventListener('click', clearFile);
        preview.append(media, remove);
        preview.hidden = false;
        drop.hidden = true;
    }

    fileInput.addEventListener('change', onFile);

    form.addEventListener('change', (event) => {
        if (event.target.matches('[data-story-bg]')) {
            textPanel.className = textPanel.className.replace(/story-bg--\S+/, 'story-bg--' + event.target.value);
        }
        if (event.target.matches('[data-story-type]')) {
            showError('');
            if (type() === 'text') {
                textArea.focus();
            }
        }
    });

    ['dragover', 'drop'].forEach((name) => {
        drop.addEventListener(name, (event) => {
            event.preventDefault();
            if (name === 'drop' && event.dataTransfer && event.dataTransfer.files.length) {
                try {
                    const transfer = new DataTransfer();
                    transfer.items.add(event.dataTransfer.files[0]);
                    fileInput.files = transfer.files;
                    onFile();
                } catch {
                    showError(t('Usa el botón para elegir el archivo.'));
                }
            }
        });
    });

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        if (sending || submit.disabled) {
            return;
        }
        if (type() === 'text' && textArea.value.trim() === '') {
            showError(t('Escribe el texto de tu historia.'));
            textArea.focus();
            return;
        }
        if (type() === 'media' && !(fileInput.files && fileInput.files.length)) {
            showError(t('Elige una foto o un video para tu historia.'));
            return;
        }
        showError('');

        const data = new FormData(form);
        if (type() === 'text') {
            data.delete('media');
        }
        const xhr = new XMLHttpRequest();
        xhr.open('POST', form.getAttribute('action'));
        xhr.setRequestHeader('Accept', 'application/json');
        xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
        xhr.responseType = 'json';
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                progressBar.style.width = Math.round((e.loaded / e.total) * 100) + '%';
            }
        });
        const done = () => {
            sending = false;
            submit.disabled = false;
            progress.hidden = true;
        };
        xhr.addEventListener('load', () => {
            const payload = xhr.response || {};
            if (xhr.status >= 200 && xhr.status < 300 && payload.ok) {
                window.location.href = payload.url;
                return;
            }
            done();
            if (xhr.status === 401) {
                window.location.href = (config.baseUrl || '') + '/login.php';
                return;
            }
            showError(payload.error || t('No se pudo publicar la historia. Inténtalo de nuevo.'));
        });
        xhr.addEventListener('error', () => {
            done();
            showError(t('Sin conexión con el servidor. Revisa tu red e inténtalo de nuevo.'));
        });
        sending = true;
        submit.disabled = true;
        progressBar.style.width = '0%';
        progress.hidden = false;
        xhr.send(data);
    });
})();
