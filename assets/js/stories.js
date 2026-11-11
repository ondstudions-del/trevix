/*
 * TREVIX · Visor de historias
 * Avance automático (fotos y textos por tiempo, videos según su duración), navegación táctil y por
 * teclado, pausa al mantener pulsado, registro de vistas, respuestas por mensaje privado y, en las
 * historias propias, quién las vio y eliminar.
 */
(function () {
    'use strict';

    const viewer = document.querySelector('[data-story-viewer]');
    const groups = viewer ? Array.from(viewer.querySelectorAll('[data-story-group]')) : [];
    if (!viewer || groups.length === 0) {
        return;
    }

    const { api, toast, t, tn } = window.Trevix;
    const HOLD_THRESHOLD = 220;
    const exitUrl = viewer.getAttribute('data-exit-url');
    const prevArrow = viewer.querySelector('[data-story-prev]');
    const nextArrow = viewer.querySelector('[data-story-next]');
    const confirmDialog = document.getElementById('confirm-dialog');

    let groupIndex = Math.min(Math.max(Number(viewer.getAttribute('data-start')) || 0, 0), groups.length - 1);
    let itemIndex = 0;
    let elapsed = 0;
    let duration = 6000;
    let ready = true;
    let lastFrame = null;
    let paused = false;
    let holding = false;
    let panelOpen = false;
    let pressStart = 0;
    let muted = true;
    const viewed = new Set();

    const items = (group) => Array.from(group.querySelectorAll('[data-story-item]'));
    const fills = (group) => Array.from(group.querySelectorAll('.story-card__fill'));
    const currentGroup = () => groups[groupIndex];
    const currentItem = () => items(currentGroup())[itemIndex];
    const videoOf = (item) => (item ? item.querySelector('video') : null);
    const audioOf = (item) => (item ? item.querySelector('[data-story-audio]') : null);

    function playMedia(media) {
        media.play().catch(() => {
            // El navegador bloqueó la reproducción con sonido: se reintenta en silencio.
            muted = true;
            media.muted = true;
            updateMuteButton();
            media.play().catch(() => {});
        });
    }

    /** Video y canción de la historia actual. Con canción, el video suena siempre en silencio. */
    function syncVideo() {
        const item = currentItem();
        const video = videoOf(item);
        const audio = audioOf(item);
        const stopped = paused || holding || panelOpen || !ready;
        if (video) {
            video.muted = audio ? true : muted;
            if (stopped) {
                video.pause();
            } else {
                playMedia(video);
            }
        }
        if (audio) {
            audio.muted = muted;
            if (stopped) {
                audio.pause();
            } else {
                playMedia(audio);
            }
        }
    }

    function rewindAudio(audio) {
        const start = Number(audio.getAttribute('data-start')) || 0;
        audio.pause();
        try {
            audio.currentTime = start;
        } catch {
            audio.addEventListener('loadedmetadata', () => { audio.currentTime = start; }, { once: true });
        }
    }

    function updateMuteButton() {
        const button = currentGroup().querySelector('[data-story-mute]');
        if (!button) {
            return;
        }
        button.hidden = !videoOf(currentItem()) && !audioOf(currentItem());
        button.setAttribute('aria-pressed', String(muted));
        button.setAttribute('aria-label', muted ? t('Activar sonido') : t('Silenciar'));
    }

    function setPaused(value) {
        paused = value;
        const button = currentGroup().querySelector('[data-story-pause]');
        if (button) {
            button.setAttribute('aria-pressed', String(value));
            button.setAttribute('aria-label', value ? t('Reanudar') : t('Pausar'));
        }
        syncVideo();
    }

    function markViewed(item, group) {
        const id = item.getAttribute('data-story-id');
        if (id === '0' || group.hasAttribute('data-own') || item.hasAttribute('data-seen') || viewed.has(id)) {
            return;
        }
        viewed.add(id);
        const data = new FormData();
        data.append('action', 'view');
        data.append('story_id', id);
        api('api/stories.php', { method: 'POST', data })
            .then(() => item.setAttribute('data-seen', ''))
            .catch(() => viewed.delete(id));
    }

    function show(nextGroup, nextItem) {
        items(currentGroup()).forEach((item) => {
            const video = videoOf(item);
            if (video) {
                video.pause();
                video.currentTime = 0;
            }
            const audio = audioOf(item);
            if (audio) {
                rewindAudio(audio);
            }
        });
        groups.forEach((group, index) => {
            group.hidden = index !== nextGroup;
        });
        groupIndex = nextGroup;
        itemIndex = nextItem;
        elapsed = 0;
        closePanel(false);

        const group = currentGroup();
        const list = items(group);
        list.forEach((item, index) => {
            item.hidden = index !== itemIndex;
        });
        fills(group).forEach((fill, index) => {
            fill.style.width = index < itemIndex ? '100%' : '0%';
        });

        const item = list[itemIndex];
        const itemAudio = audioOf(item);
        if (itemAudio) {
            rewindAudio(itemAudio);
        }
        const seconds = Number(item.getAttribute('data-seconds')) || 6;
        duration = seconds * 1000;
        const video = videoOf(item);
        ready = !video;
        if (video) {
            const start = () => {
                duration = Math.min(seconds, Number.isFinite(video.duration) && video.duration > 0 ? video.duration : seconds) * 1000;
                ready = true;
                syncVideo();
            };
            if (video.readyState >= 1) {
                start();
            } else {
                video.addEventListener('loadedmetadata', start, { once: true });
                video.addEventListener('error', () => { ready = true; }, { once: true });
            }
        }

        const time = group.querySelector('[data-story-time]');
        if (time) {
            time.textContent = item.getAttribute('data-time') || '';
        }
        group.querySelectorAll('[data-story-current]').forEach((input) => {
            input.value = item.getAttribute('data-story-id');
        });
        group.querySelectorAll('[data-story-report]').forEach((link) => {
            const reportUrl = new URL(link.href, window.location.href);
            reportUrl.searchParams.set('id', item.getAttribute('data-story-id'));
            link.href = reportUrl.toString();
        });
        group.querySelectorAll('[data-story-gift]').forEach((link) => {
            const giftUrl = new URL(link.href, window.location.href);
            giftUrl.searchParams.set('ref', item.getAttribute('data-story-id'));
            link.href = giftUrl.toString();
        });
        const views = group.querySelector('[data-story-views]');
        if (views) {
            views.textContent = item.getAttribute('data-views') || '0';
        }

        if (prevArrow) prevArrow.disabled = groupIndex === 0;
        if (nextArrow) nextArrow.disabled = groupIndex === groups.length - 1;

        const url = new URL(window.location.href);
        url.searchParams.set('u', group.getAttribute('data-username'));
        window.history.replaceState(null, '', url);
        setPaused(false);
        updateMuteButton();
        markViewed(item, group);
    }

    /** Al entrar en otra cuenta se empieza por su primera historia sin ver. */
    function enterGroup(index) {
        show(index, Number(groups[index].getAttribute('data-first-unseen')) || 0);
    }

    function next() {
        if (itemIndex < items(currentGroup()).length - 1) {
            show(groupIndex, itemIndex + 1);
        } else if (groupIndex < groups.length - 1) {
            enterGroup(groupIndex + 1);
        } else {
            window.location.href = exitUrl;
        }
    }

    function prev() {
        if (itemIndex > 0) {
            show(groupIndex, itemIndex - 1);
        } else if (groupIndex > 0) {
            show(groupIndex - 1, 0);
        } else {
            show(0, 0);
        }
    }

    function frame(timestamp) {
        if (lastFrame === null) {
            lastFrame = timestamp;
        }
        const delta = timestamp - lastFrame;
        lastFrame = timestamp;

        if (!paused && !holding && !panelOpen && ready) {
            const video = videoOf(currentItem());
            elapsed = video ? video.currentTime * 1000 : elapsed + delta;
            const fill = fills(currentGroup())[itemIndex];
            if (fill) {
                fill.style.width = Math.min(100, (elapsed / duration) * 100) + '%';
            }
            if (elapsed >= duration || (video && video.ended)) {
                next();
            }
        }
        window.requestAnimationFrame(frame);
    }

    /* ---------- Quién vio la historia (solo las propias) ---------- */
    function closePanel(resume = true) {
        const panel = currentGroup().querySelector('[data-story-viewers-panel]');
        if (panel && !panel.hidden) {
            panel.hidden = true;
        }
        if (panelOpen) {
            panelOpen = false;
            if (resume) {
                syncVideo();
            }
        }
    }

    async function openViewers() {
        const group = currentGroup();
        const panel = group.querySelector('[data-story-viewers-panel]');
        const list = group.querySelector('[data-story-viewers-list]');
        const title = group.querySelector('[data-story-viewers-title]');
        const id = currentItem().getAttribute('data-story-id');
        if (!panel || id === '0') {
            return;
        }
        panelOpen = true;
        syncVideo();
        panel.hidden = false;
        list.replaceChildren();
        title.textContent = t('Cargando…');
        try {
            const data = await api('api/stories.php?action=viewers&id=' + encodeURIComponent(id));
            title.textContent = tn(data.count, '{n} vista', '{n} vistas');
            if (data.viewers.length === 0) {
                const empty = document.createElement('li');
                empty.className = 'story-viewers__empty';
                empty.textContent = t('Todavía nadie la ha visto.');
                list.appendChild(empty);
            }
            data.viewers.forEach((v) => {
                const li = document.createElement('li');
                const link = document.createElement('a');
                link.className = 'story-viewers__item';
                link.href = v.url;
                link.innerHTML = v.avatar;
                const name = document.createElement('span');
                name.className = 'story-viewers__name';
                name.textContent = v.display_name;
                const meta = document.createElement('span');
                meta.className = 'story-viewers__meta';
                meta.textContent = '@' + v.username + ' · ' + v.viewed;
                name.appendChild(meta);
                link.appendChild(name);
                li.appendChild(link);
                list.appendChild(li);
            });
        } catch (error) {
            title.textContent = t('Vistas');
            toast(error.message, 'error');
        }
    }

    function confirmAction(message, label) {
        if (!confirmDialog || typeof confirmDialog.showModal !== 'function') {
            return Promise.resolve(window.confirm(message));
        }
        confirmDialog.querySelector('[data-confirm-text]').textContent = message;
        confirmDialog.querySelector('[data-confirm-ok]').textContent = label;
        confirmDialog.returnValue = '';
        confirmDialog.showModal();
        return new Promise((resolve) => {
            confirmDialog.addEventListener('close', () => resolve(confirmDialog.returnValue === 'ok'), { once: true });
        });
    }

    /* ---------- Eventos ---------- */
    viewer.addEventListener('pointerdown', (event) => {
        if (event.target.closest('[data-story-tap]')) {
            holding = true;
            pressStart = performance.now();
            syncVideo();
        }
    });

    viewer.addEventListener('pointerup', (event) => {
        const tap = event.target.closest('[data-story-tap]');
        const wasHold = performance.now() - pressStart > HOLD_THRESHOLD;
        const wasHolding = holding;
        holding = false;
        if (tap && wasHolding && !wasHold) {
            tap.getAttribute('data-story-tap') === 'next' ? next() : prev();
        } else {
            syncVideo();
        }
    });

    viewer.addEventListener('pointercancel', () => {
        holding = false;
        syncVideo();
    });

    viewer.addEventListener('click', (event) => {
        if (event.target.closest('[data-story-pause]')) {
            setPaused(!paused);
        } else if (event.target.closest('[data-story-mute]')) {
            muted = !muted;
            updateMuteButton();
            syncVideo();
        } else if (event.target.closest('[data-story-viewers]')) {
            openViewers();
        } else if (event.target.closest('[data-story-viewers-close]')) {
            closePanel();
        } else if (event.target.closest('[data-story-prev]')) {
            show(Math.max(0, groupIndex - 1), 0);
        } else if (event.target.closest('[data-story-next]')) {
            if (groupIndex < groups.length - 1) enterGroup(groupIndex + 1);
        }
    });

    viewer.addEventListener('submit', async (event) => {
        const form = event.target;
        if (form.matches('[data-story-poll]')) {
            event.preventDefault();
            const button = event.submitter;
            if (!button || button.disabled) return;
            const data = new FormData(form);
            data.set('choice', button.value);
            const options = Array.from(form.querySelectorAll('.story-poll__option'));
            options.forEach((option) => { option.disabled = true; });
            try {
                const result = await api('api/stories.php', { method: 'POST', data });
                const total = Math.max(1, result.total);
                options.forEach((option, index) => {
                    const percent = Math.round((result.counts[index] * 100) / total);
                    option.style.setProperty('--poll-percent', percent + '%');
                    option.classList.toggle('is-chosen', index === result.viewer_choice);
                    option.querySelector('[data-poll-percent]').textContent = percent + '%';
                });
                form.classList.add('has-results');
            } catch (error) {
                toast(error.message, 'error');
                options.forEach((option) => { option.disabled = false; });
            }
        } else if (form.matches('[data-story-reply-form]')) {
            event.preventDefault();
            const input = form.querySelector('[data-story-reply]');
            if (!input || input.value.trim() === '') {
                return;
            }
            const button = form.querySelector('button[type="submit"]');
            button.disabled = true;
            try {
                await api('api/stories.php', { method: 'POST', data: new FormData(form) });
                input.value = '';
                input.blur();
                toast(t('Respuesta enviada por mensaje privado'), 'success');
                setPaused(false);
            } catch (error) {
                toast(error.message, 'error');
            } finally {
                button.disabled = false;
            }
        } else if (form.matches('[data-story-delete]')) {
            event.preventDefault();
            setPaused(true);
            if (!(await confirmAction(t('¿Eliminar esta historia? Se borrará para todos y no se puede deshacer.'), t('Eliminar')))) {
                setPaused(false);
                return;
            }
            try {
                const result = await api('api/stories.php', { method: 'POST', data: new FormData(form) });
                window.location.href = result.url;
            } catch (error) {
                toast(error.message, 'error');
                setPaused(false);
            }
        }
    });

    viewer.addEventListener('focusin', (event) => {
        if (event.target.matches('[data-story-reply]')) setPaused(true);
    });

    document.addEventListener('keydown', (event) => {
        if (event.target.matches('input, textarea') || (confirmDialog && confirmDialog.open)) {
            if (event.key === 'Escape' && event.target.matches('input, textarea')) event.target.blur();
            return;
        }
        if (panelOpen) {
            if (event.key === 'Escape') closePanel();
            return;
        }
        if (event.key === 'ArrowRight') next();
        else if (event.key === 'ArrowLeft') prev();
        else if (event.key === ' ') {
            event.preventDefault();
            setPaused(!paused);
        } else if (event.key === 'Escape') window.location.href = exitUrl;
    });

    document.addEventListener('visibilitychange', () => {
        if (document.hidden) setPaused(true);
    });

    enterGroup(groupIndex);
    window.requestAnimationFrame(frame);
})();
