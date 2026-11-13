/*
 * TREVIX · Música
 * - Reproductores de canciones ([data-song-player]): uno sonando a la vez y, en publicaciones e
 *   historias, solo el fragmento elegido (data-start / data-end).
 * - Campos para adjuntar canciones ([data-song-field]) con el selector #music-picker: busca en la
 *   biblioteca (api/music.php) y, en modo clip, deja elegir dónde empieza el fragmento.
 * - Formulario de subida del artista ([data-song-upload]) con barra de progreso.
 */
(function () {
    'use strict';

    const { $, $$, config, toast, t } = window.Trevix;
    const base = config.baseUrl || '';
    const ICON_PLAY = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/></svg>';
    const ICON_PAUSE = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="14" y="3" width="5" height="18" rx="1"/><rect x="5" y="3" width="5" height="18" rx="1"/></svg>';
    const ICON_MUSIC = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>';

    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
    }

    function absolute(path) {
        return path ? base + '/' + String(path).replace(/^\//, '') : '';
    }

    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) {
            node.className = className;
        }
        if (text !== undefined) {
            node.textContent = text;
        }
        return node;
    }

    /* =====================================================================
     * Reproductores
     * ===================================================================== */
    let current = null;

    function bounds(audio) {
        const start = Number(audio.dataset.start || 0);
        const end = Number(audio.dataset.end || 0);
        return { start, end: end > start ? end : (Number.isFinite(audio.duration) ? audio.duration : Infinity) };
    }

    function seek(audio, time) {
        try {
            audio.currentTime = time;
        } catch {
            audio.dataset.pendingStart = String(time);
        }
    }

    function playAudio(audio) {
        const { start, end } = bounds(audio);
        if (audio.currentTime < start || audio.currentTime >= end - 0.25) {
            if (audio.readyState === 0) {
                audio.dataset.pendingStart = String(start);
            }
            seek(audio, start);
        }
        const promise = audio.play();
        if (promise && promise.catch) {
            promise.catch(() => toast(t('No se pudo reproducir la canción.'), 'error'));
        }
    }

    /** La etiqueta puede venir en español o ya traducida: «Reproducir …» ↔ «Pausar …». */
    function swapLabelPrefix(button, from, to) {
        const label = button.getAttribute('aria-label');
        const match = [[t(from), t(to)], [from, to]].find(([prefix]) => label.startsWith(prefix));
        if (match) {
            button.setAttribute('aria-label', match[1] + label.slice(match[0].length));
        }
    }

    function stopAll(except) {
        $$('audio').forEach((audio) => {
            if (audio !== except && !audio.paused) {
                audio.pause();
            }
        });
    }

    document.addEventListener('click', (event) => {
        const button = event.target.closest('[data-song-toggle]');
        if (!button) {
            return;
        }
        event.preventDefault();
        const player = button.closest('[data-song-player]');
        const audio = player ? $('audio', player) : null;
        if (!audio) {
            return;
        }
        if (audio.paused) {
            playAudio(audio);
        } else {
            audio.pause();
        }
    });

    function playerOf(target) {
        return target instanceof HTMLAudioElement ? target.closest('[data-song-player]') : null;
    }

    document.addEventListener('loadedmetadata', (event) => {
        const audio = event.target;
        if (audio instanceof HTMLAudioElement && audio.dataset.pendingStart) {
            seek(audio, Number(audio.dataset.pendingStart));
            delete audio.dataset.pendingStart;
        }
    }, true);

    document.addEventListener('play', (event) => {
        if (!(event.target instanceof HTMLMediaElement)) {
            return;
        }
        if (event.target instanceof HTMLAudioElement) {
            stopAll(event.target);
            current = event.target;
        }
        const player = playerOf(event.target);
        if (player) {
            player.classList.add('is-playing');
            const button = $('[data-song-toggle]', player);
            if (button) {
                swapLabelPrefix(button, 'Reproducir', 'Pausar');
            }
        }
    }, true);

    function markStopped(audio) {
        const player = playerOf(audio);
        if (!player) {
            return;
        }
        player.classList.remove('is-playing');
        const button = $('[data-song-toggle]', player);
        if (button) {
            swapLabelPrefix(button, 'Pausar', 'Reproducir');
        }
    }

    document.addEventListener('pause', (event) => {
        if (event.target === current) {
            current = null;
        }
        markStopped(event.target);
    }, true);

    document.addEventListener('ended', (event) => {
        markStopped(event.target);
        if (event.target instanceof HTMLAudioElement) {
            seek(event.target, bounds(event.target).start);
        }
    }, true);

    document.addEventListener('timeupdate', (event) => {
        const audio = event.target;
        const player = playerOf(audio);
        if (!player) {
            return;
        }
        const { start, end } = bounds(audio);
        if (audio.currentTime >= end) {
            audio.pause();
            seek(audio, start);
        }
        const total = end - start;
        const position = Math.min(Math.max(audio.currentTime - start, 0), total);
        const bar = $('[data-song-progress]', player);
        if (bar && Number.isFinite(total) && total > 0) {
            bar.style.width = (position / total * 100).toFixed(1) + '%';
        }
        const time = $('[data-song-time]', player);
        if (time && Number.isFinite(total)) {
            time.textContent = clock(audio.paused && position === 0 ? total : total - position);
        }
    }, true);

    /** Tarjeta de canción (misma estructura que partials/song-chip.php). */
    const CLIP_SECONDS = Number(config.limits && config.limits.song_clip_seconds) || 30;

    function songChip(song, mode, start) {
        const clipLength = CLIP_SECONDS;
        const from = mode === 'clip' ? start : 0;
        const to = mode === 'clip' ? Math.min(song.duration, from + clipLength) : 0;
        const length = mode === 'clip' ? to - from : song.duration;
        const songUrl = base + '/music.php?id=' + song.id;

        const root = el('div', 'song-chip song-chip--md');
        root.setAttribute('data-song-player', '');

        const play = el('button', 'song-chip__play js-only');
        play.type = 'button';
        play.setAttribute('data-song-toggle', '');
        play.setAttribute('aria-label', t('Reproducir «{title}»', { title: song.title }));
        play.innerHTML = '<span class="song-chip__icon-play">' + ICON_PLAY + '</span><span class="song-chip__icon-pause">' + ICON_PAUSE + '</span>';

        const cover = el('a', 'song-chip__cover');
        cover.href = songUrl;
        cover.tabIndex = -1;
        cover.setAttribute('aria-hidden', 'true');
        if (song.cover) {
            const img = el('img');
            img.src = song.cover;
            img.alt = '';
            cover.appendChild(img);
        } else {
            cover.innerHTML = ICON_MUSIC;
        }

        const info = el('span', 'song-chip__info');
        const title = el('a', 'song-chip__title', song.title);
        title.href = songUrl;
        if (song.is_explicit) {
            const explicit = el('abbr', 'song-chip__explicit', 'E');
            explicit.title = t('Contenido explícito');
            title.append(' ', explicit);
        }
        const artist = el('span', 'song-chip__artist', song.artist.display_name + (song.featuring ? ' · feat. ' + song.featuring : '')
            + (song.source && song.source !== 'trevix' && song.source !== 'original' ? ' · ' + song.source_label : ''));
        const bar = el('span', 'song-chip__bar');
        bar.setAttribute('aria-hidden', 'true');
        const progress = el('span');
        progress.setAttribute('data-song-progress', '');
        bar.appendChild(progress);
        info.append(title, artist, bar);

        const time = el('span', 'song-chip__time', clock(length));
        time.setAttribute('data-song-time', '');

        const audio = el('audio');
        audio.preload = 'none';
        audio.src = song.src;
        audio.dataset.start = String(from);
        audio.dataset.end = String(to);

        root.append(play, cover, info, time, audio);
        return root;
    }

    /* =====================================================================
     * Videos grabados sobre la canción (video[data-song-sync], cámara de reels de la app): el video no tiene
     * sonido propio y la canción de la publicación suena desde su inicio al compás del video.
     * ===================================================================== */
    const DRIFT = 0.3;

    function syncedAudio(video) {
        const post = video.closest('.post');
        return post ? $('.post__song audio', post) : null;
    }

    function syncTo(video, audio) {
        const target = bounds(audio).start + video.currentTime;
        if (Math.abs(audio.currentTime - target) > DRIFT) {
            if (audio.readyState === 0) {
                audio.dataset.pendingStart = String(target);
            }
            seek(audio, target);
        }
    }

    function isSynced(target) {
        return target instanceof HTMLVideoElement && target.hasAttribute('data-song-sync');
    }

    document.addEventListener('play', (event) => {
        const video = event.target;
        const audio = isSynced(video) ? syncedAudio(video) : null;
        if (!audio) {
            return;
        }
        syncTo(video, audio);
        const promise = audio.play();
        if (promise && promise.catch) {
            promise.catch(() => {});
        }
    }, true);

    ['pause', 'ended'].forEach((type) => {
        document.addEventListener(type, (event) => {
            const audio = isSynced(event.target) ? syncedAudio(event.target) : null;
            if (audio && !audio.paused) {
                audio.pause();
            }
        }, true);
    });

    ['seeked', 'timeupdate'].forEach((type) => {
        document.addEventListener(type, (event) => {
            const video = event.target;
            const audio = isSynced(video) ? syncedAudio(video) : null;
            if (audio && !video.paused) {
                syncTo(video, audio);
            }
        }, true);
    });

    /* =====================================================================
     * Música de las fotos y textos con canción ([data-post-song][data-autoplay]): suena sola, en bucle, mientras la
     * publicación es la que más se ve en pantalla. El botón de sonido la silencia en todas las publicaciones y la
     * preferencia queda guardada en el navegador. Si el navegador exige un toque antes de reproducir, empieza con
     * el primer toque o tecla.
     * ===================================================================== */
    (function feedSongs() {
        if (!('IntersectionObserver' in window)) {
            return;
        }
        const KEY = 'trevix.feedSound';
        let muted = false;
        try {
            muted = window.localStorage.getItem(KEY) === 'off';
        } catch {
            muted = false;
        }
        const ratios = new Map();
        let active = null;
        let blocked = false;

        function paintMute() {
            $$('[data-song-mute]').forEach((button) => {
                button.setAttribute('aria-pressed', String(muted));
                button.setAttribute('aria-label', muted ? t('Activar la música de las publicaciones') : t('Silenciar la música de las publicaciones'));
                const box = button.closest('[data-post-song]');
                if (box) {
                    box.classList.toggle('is-muted', muted);
                }
            });
        }

        function stop() {
            if (active) {
                active.pause();
                const box = active.closest('[data-post-song]');
                if (box) {
                    box.classList.remove('is-playing');
                }
                active = null;
            }
        }

        function mostVisible() {
            let top = null;
            let max = 0.55;
            ratios.forEach((ratio, article) => {
                if (ratio >= max && article.isConnected && !article.hidden) {
                    max = ratio;
                    top = article;
                }
            });
            return top ? $('[data-post-song][data-autoplay] audio', top) : null;
        }

        function videoWithSound() {
            return $$('video').some((video) => !video.paused && !video.muted && !video.hasAttribute('data-song-sync'));
        }

        function update() {
            const audio = muted || document.hidden ? null : mostVisible();
            if (audio === active) {
                return;
            }
            stop();
            if (!audio || videoWithSound()) {
                return;
            }
            active = audio;
            const { start, end } = bounds(audio);
            if (audio.currentTime < start || audio.currentTime >= end - 0.25) {
                if (audio.readyState === 0) {
                    audio.dataset.pendingStart = String(start);
                }
                seek(audio, start);
            }
            const box = audio.closest('[data-post-song]');
            box.classList.add('is-playing');
            const promise = audio.play();
            if (promise && promise.catch) {
                promise.catch(() => {
                    blocked = true;
                    box.classList.remove('is-playing');
                    if (active === audio) {
                        active = null;
                    }
                });
            }
        }

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => ratios.set(entry.target, entry.intersectionRatio));
            update();
        }, { threshold: [0, 0.25, 0.55, 0.75, 1] });

        function watch(root) {
            $$('[data-post-song][data-autoplay]', root).forEach((box) => {
                const article = box.closest('article.post');
                if (article && !article.dataset.songWatched) {
                    article.dataset.songWatched = '1';
                    observer.observe(article);
                }
            });
            paintMute();
        }

        watch(document);
        new MutationObserver((records) => {
            records.forEach((record) => record.addedNodes.forEach((node) => {
                if (node.nodeType === 1) {
                    watch(node);
                }
            }));
        }).observe(document.body, { childList: true, subtree: true });

        document.addEventListener('click', (event) => {
            const button = event.target.closest('[data-song-mute]');
            if (!button) {
                return;
            }
            event.preventDefault();
            muted = !muted;
            try {
                window.localStorage.setItem(KEY, muted ? 'off' : 'on');
            } catch {
                /* sin almacenamiento: la preferencia dura hasta recargar */
            }
            paintMute();
            if (muted) {
                stop();
            } else {
                blocked = false;
                update();
            }
        });

        ['pointerdown', 'keydown'].forEach((type) => document.addEventListener(type, () => {
            if (blocked) {
                blocked = false;
                window.setTimeout(update, 0);
            }
        }, true));

        document.addEventListener('visibilitychange', () => (document.hidden ? stop() : update()));

        // Un video con sonido o una canción que la persona pone a mano tienen prioridad.
        document.addEventListener('play', (event) => {
            const media = event.target;
            if (media !== active && active && media instanceof HTMLMediaElement && !isSynced(media)) {
                stop();
            }
        }, true);

        document.addEventListener('timeupdate', (event) => {
            const audio = event.target;
            if (audio === active) {
                const { start, end } = bounds(audio);
                if (audio.currentTime >= end - 0.05) {
                    seek(audio, start);
                }
            }
        }, true);

        document.addEventListener('ended', (event) => {
            if (event.target === active) {
                seek(active, bounds(active).start);
                active.play().catch(() => {});
            }
        }, true);
    })();

    /* =====================================================================
     * Campos de canción y selector
     * ===================================================================== */
    const picker = $('#music-picker');

    function setField(field, song, start) {
        const idInput = $('[data-song-id]', field);
        const startInput = $('[data-song-start]', field);
        const mode = field.getAttribute('data-song-mode') || 'clip';
        idInput.disabled = false;
        idInput.value = song ? String(song.id) : '';
        if (startInput) {
            startInput.disabled = false;
            startInput.value = song ? String(start || 0) : '0';
        }
        const chip = $('[data-song-chip]', field);
        chip.replaceChildren();
        if (song) {
            chip.appendChild(songChip(song, mode, start || 0));
        }
        $('[data-song-selected]', field).hidden = !song;
        const add = $('.song-field__add', field);
        if (add) {
            add.hidden = Boolean(song);
        }
        field.dispatchEvent(new CustomEvent('trevix:song-change', { bubbles: true, detail: { song, start } }));
    }

    function clearField(field) {
        stopAll(null);
        setField(field, null, 0);
    }

    /** El campo lleva una canción (elegida ahora o la que ya tenía, aunque ya no esté disponible). */
    function hasSong(field) {
        const input = field ? $('[data-song-id]', field) : null;
        if (!input) {
            return false;
        }
        return input.disabled ? Boolean($('[data-song-chip] .song-chip', field)) : input.value !== '';
    }

    window.Trevix.music = { setField, clearField, hasSong, songChip, clock };

    /* Biblioteca: cambiar de género aplica el filtro. */
    document.addEventListener('change', (event) => {
        const select = event.target;
        if (select instanceof HTMLSelectElement && select.matches('[data-music-filters] select[data-autosubmit]') && select.form) {
            select.form.submit();
        }
    });

    document.addEventListener('click', (event) => {
        const remove = event.target.closest('[data-song-remove]');
        if (remove) {
            const field = remove.closest('[data-song-field]');
            if (field) {
                clearField(field);
            }
            return;
        }
        const pick = event.target.closest('[data-song-pick], [data-song-open]');
        if (!pick || !picker) {
            return;
        }
        let field = pick.closest('[data-song-field]');
        if (!field) {
            const scope = pick.closest('form') || document;
            field = $('[data-song-field]', scope);
        }
        if (field) {
            event.preventDefault();
            openPicker(field);
        }
    });

    if (!picker) {
        return;
    }

    const q = $('[data-picker-q]', picker);
    const results = $('[data-picker-results]', picker);
    const empty = $('[data-picker-empty]', picker);
    const more = $('[data-picker-more]', picker);
    const footer = $('[data-picker-footer]', picker);
    const startRange = $('[data-picker-start]', picker);
    const previewButton = $('[data-picker-preview]', picker);
    const previewAudio = $('[data-picker-audio]', picker);
    const steps = {
        search: $('[data-picker-step="search"]', picker),
        clip: $('[data-picker-step="clip"]', picker),
    };

    let targetField = null;
    let chosen = null;
    let page = 1;
    let searchTimer = null;
    let requestId = 0;

    function clipLength() {
        return Math.min(CLIP_SECONDS, chosen ? chosen.duration : CLIP_SECONDS);
    }

    function showStep(name) {
        steps.search.hidden = name !== 'search';
        steps.clip.hidden = name !== 'clip';
        footer.hidden = name !== 'clip';
        $('[data-picker-title]', picker).textContent = name === 'clip' ? t('Elige el fragmento') : t('Añadir música');
    }

    function sortValue() {
        const checked = $('[data-picker-sort]:checked', picker);
        return checked ? checked.value : 'popular';
    }

    const CREDIT = t('Incluye canciones de Audius (audius.co), de sus artistas, y música libre de Free To Use (freetouse.com/music), con el crédito del artista.');

    async function search(reset) {
        if (reset) {
            page = 1;
        }
        const id = ++requestId;
        const params = new URLSearchParams({ action: 'search', q: q.value.trim(), sort: sortValue(), page: String(page) });
        const credit = $('[data-picker-credit]', picker);
        more.hidden = true;
        if (reset) {
            results.setAttribute('aria-busy', 'true');
            empty.hidden = true;
        }
        try {
            const data = await window.Trevix.api('api/music.php?' + params.toString());
            if (id !== requestId) {
                return;
            }
            if (reset) {
                results.replaceChildren();
            }
            data.items.forEach((item) => results.appendChild(item.song ? resultItem(item.song) : catalogItem(item.track)));
            const none = results.children.length === 0;
            empty.hidden = !none;
            empty.textContent = q.value.trim() !== ''
                ? t('No encontramos canciones con «{q}».', { q: q.value.trim() })
                : t('No hay canciones para mostrar. Prueba a buscar.');
            const notes = [];
            if (data.unavailable && data.unavailable.length) {
                notes.push(t('{sources} no respondió: por ahora ves el resto del catálogo.', { sources: data.unavailable.join(' ' + t('y') + ' ') }));
            }
            if (data.items.some((item) => item.source !== 'trevix')) {
                notes.push(CREDIT);
            }
            credit.textContent = notes.join(' ');
            credit.hidden = notes.length === 0;
            more.hidden = !data.hasMore;
        } catch (error) {
            if (id === requestId) {
                empty.hidden = false;
                empty.textContent = error.message;
            }
        } finally {
            results.removeAttribute('aria-busy');
        }
    }

    function resultItem(song) {
        const li = el('li', 'music-picker__item');
        const preview = el('button', 'music-picker__preview');
        preview.type = 'button';
        preview.setAttribute('aria-label', t('Escuchar «{title}»', { title: song.title }));
        if (song.cover) {
            const img = el('img');
            img.src = song.cover;
            img.alt = '';
            img.loading = 'lazy';
            preview.appendChild(img);
        } else {
            preview.innerHTML = ICON_MUSIC;
        }
        const overlay = el('span', 'music-picker__preview-icon');
        overlay.innerHTML = '<span class="music-picker__icon-play">' + ICON_PLAY + '</span><span class="music-picker__icon-pause">' + ICON_PAUSE + '</span>';
        preview.appendChild(overlay);
        preview.addEventListener('click', () => togglePreview(song, 0, preview));

        const info = el('span', 'music-picker__info');
        const title = el('strong', '', song.title);
        if (song.is_explicit) {
            title.append(' ', el('abbr', 'song-chip__explicit', 'E'));
        }
        info.append(title, el('span', '', song.artist.display_name + (song.featuring ? ' · feat. ' + song.featuring : '') + ' · ' + clock(song.duration)));

        const choose = el('button', 'btn btn--primary btn--sm', t('Elegir'));
        choose.type = 'button';
        choose.addEventListener('click', () => pickSong(song));
        li.append(preview, info, choose);
        return li;
    }

    /** Pista de un catálogo externo: se escucha desde el catálogo y, al elegirla, el servidor la guarda como canción. */
    function catalogItem(track) {
        const li = el('li', 'music-picker__item');
        const preview = el('button', 'music-picker__preview');
        preview.type = 'button';
        preview.setAttribute('aria-label', t('Escuchar «{title}»', { title: track.title }));
        if (track.cover) {
            const img = el('img');
            img.src = track.cover;
            img.alt = '';
            img.loading = 'lazy';
            preview.appendChild(img);
        } else {
            preview.innerHTML = ICON_MUSIC;
        }
        const overlay = el('span', 'music-picker__preview-icon');
        overlay.innerHTML = '<span class="music-picker__icon-play">' + ICON_PLAY + '</span><span class="music-picker__icon-pause">' + ICON_PAUSE + '</span>';
        preview.appendChild(overlay);
        preview.addEventListener('click', () => togglePreview({ src: track.preview }, 0, preview));

        const info = el('span', 'music-picker__info');
        info.append(el('strong', '', track.title), el('span', '', track.artist + ' · ' + track.genre_label + ' · ' + clock(track.duration)));

        const choose = el('button', 'btn btn--primary btn--sm', t('Elegir'));
        choose.type = 'button';
        choose.addEventListener('click', async () => {
            choose.disabled = true;
            const data = new FormData();
            data.append('action', 'import');
            data.append('source', track.source);
            data.append('external_id', track.external_id);
            try {
                const response = await window.Trevix.api('api/music.php', { method: 'POST', data });
                pickSong(response.song);
            } catch (error) {
                toast(error.message, 'error');
            } finally {
                choose.disabled = false;
            }
        });
        li.append(preview, info, choose);
        return li;
    }

    function pickSong(song) {
        stopPreview();
        chosen = song;
        const mode = targetField.getAttribute('data-song-mode') || 'clip';
        if (mode !== 'clip') {
            setField(targetField, song, 0);
            picker.close();
            return;
        }
        const length = clipLength();
        const max = Math.max(0, song.duration - length);
        const currentStart = Number(($('[data-song-id]', targetField).value === String(song.id) && $('[data-song-start]', targetField))
            ? $('[data-song-start]', targetField).value : 0) || 0;
        startRange.max = String(max);
        startRange.value = String(Math.min(currentStart, max));
        startRange.disabled = max === 0;
        $('[data-picker-length]', picker).textContent = String(length);
        const selected = $('[data-picker-selected]', picker);
        selected.replaceChildren(songChip(song, 'full', 0));
        $('audio', selected).remove();
        $('[data-song-toggle]', selected).remove();
        updateRangeLabels();
        showStep('clip');
    }

    function updateRangeLabels() {
        const from = Number(startRange.value);
        $('[data-picker-from]', picker).textContent = clock(from);
        $('[data-picker-to]', picker).textContent = clock(from + clipLength());
    }

    let previewOwner = null;
    let previewEnd = Infinity;

    function togglePreview(song, start, owner, end) {
        if (previewOwner === owner && !previewAudio.paused) {
            stopPreview();
            return;
        }
        stopPreview();
        previewOwner = owner;
        previewEnd = end || Infinity;
        if (previewAudio.getAttribute('src') !== song.src) {
            previewAudio.src = song.src;
        }
        previewAudio.dataset.pendingStart = String(start);
        seek(previewAudio, start);
        owner.classList.add('is-playing');
        previewAudio.play().catch(() => {
            owner.classList.remove('is-playing');
            toast(t('No se pudo reproducir la canción.'), 'error');
        });
    }

    function stopPreview() {
        if (!previewAudio.paused) {
            previewAudio.pause();
        }
        if (previewOwner) {
            previewOwner.classList.remove('is-playing');
            previewOwner = null;
        }
    }

    previewAudio.addEventListener('timeupdate', () => {
        if (previewAudio.currentTime >= previewEnd) {
            stopPreview();
        }
    });
    previewAudio.addEventListener('ended', stopPreview);

    previewButton.addEventListener('click', () => {
        if (!chosen) {
            return;
        }
        const from = Number(startRange.value);
        togglePreview(chosen, from, previewButton, from + clipLength());
    });

    startRange.addEventListener('input', () => {
        updateRangeLabels();
        if (previewOwner === previewButton) {
            stopPreview();
        }
    });

    $('[data-picker-back]', picker).addEventListener('click', () => {
        stopPreview();
        showStep('search');
    });

    $('[data-picker-confirm]', picker).addEventListener('click', () => {
        if (chosen && targetField) {
            setField(targetField, chosen, Number(startRange.value));
        }
        picker.close();
    });

    q.addEventListener('input', () => {
        window.clearTimeout(searchTimer);
        searchTimer = window.setTimeout(() => search(true), 300);
    });
    $$('[data-picker-sort]', picker).forEach((radio) => radio.addEventListener('change', () => {
        stopPreview();
        search(true);
    }));
    more.addEventListener('click', () => {
        page += 1;
        search(false);
    });

    picker.addEventListener('close', () => {
        stopPreview();
        targetField = null;
    });

    let loaded = false;

    function openPicker(field) {
        stopAll(null);
        targetField = field;
        chosen = null;
        showStep('search');
        if (!picker.open) {
            picker.showModal();
        }
        if (!loaded) {
            loaded = true;
            search(true);
        }
        q.focus();
    }

    /** Abrir el selector desde fuera (p. ej. «Usar en publicación» con la canción ya elegida). */
    window.Trevix.music.open = openPicker;
    window.Trevix.music.choose = (field, song) => {
        openPicker(field);
        pickSong(song);
    };
})();

/* =========================================================================
 * Subida de canciones (panel del artista)
 * ========================================================================= */
(function () {
    'use strict';

    const { $, config, toast, formatBytes, t } = window.Trevix;
    const form = $('[data-song-upload]');
    if (!form) {
        return;
    }
    const rules = (config.uploads && config.uploads.audio) || { maxBytes: 0, extensions: ['mp3', 'm4a'], minSeconds: 15, maxSeconds: 900 };
    const fileInput = $('[data-song-audio]', form);
    const fileLabel = $('[data-song-audio-name]', form);
    const errorBox = $('[data-song-error]', form);
    const progress = $('[data-song-progress-box]', form);
    const bar = $('[data-song-progress-bar]', form);
    const submit = $('[type="submit"]', form);
    let sending = false;

    function showError(message) {
        errorBox.textContent = message;
        errorBox.hidden = !message;
    }

    function readDuration(file) {
        return new Promise((resolve) => {
            const audio = document.createElement('audio');
            const url = URL.createObjectURL(file);
            audio.preload = 'metadata';
            audio.onloadedmetadata = () => {
                URL.revokeObjectURL(url);
                resolve(Number.isFinite(audio.duration) ? audio.duration : null);
            };
            audio.onerror = () => {
                URL.revokeObjectURL(url);
                resolve(null);
            };
            audio.src = url;
        });
    }

    async function checkFile() {
        const file = fileInput.files && fileInput.files[0];
        if (!file) {
            fileLabel.textContent = t('MP3 o M4A, hasta {size}', { size: formatBytes(rules.maxBytes) });
            return true;
        }
        const extension = (file.name.split('.').pop() || '').toLowerCase();
        if (!rules.extensions.includes(extension)) {
            showError(t('Formato no permitido. Sube un archivo MP3 o M4A.'));
            fileInput.value = '';
            return false;
        }
        if (file.size > rules.maxBytes) {
            showError(t('La canción puede pesar como máximo {size}.', { size: formatBytes(rules.maxBytes) }));
            fileInput.value = '';
            return false;
        }
        const seconds = await readDuration(file);
        let text = file.name + ' · ' + formatBytes(file.size);
        if (seconds !== null) {
            if (seconds < rules.minSeconds - 0.5) {
                showError(t('La canción debe durar al menos {n} segundos.', { n: rules.minSeconds }));
                fileInput.value = '';
                return false;
            }
            if (seconds > rules.maxSeconds + 0.5) {
                showError(t('La canción puede durar como máximo {n} minutos.', { n: Math.floor(rules.maxSeconds / 60) }));
                fileInput.value = '';
                return false;
            }
            text += ' · ' + window.Trevix.music.clock(seconds);
        }
        fileLabel.textContent = text;
        showError('');
        return true;
    }

    fileInput.addEventListener('change', checkFile);

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        if (sending) {
            return;
        }
        if (!form.reportValidity()) {
            return;
        }
        if (!fileInput.files || !fileInput.files[0]) {
            showError(t('Elige el archivo de la canción (MP3 o M4A).'));
            return;
        }
        showError('');
        const xhr = new XMLHttpRequest();
        xhr.open('POST', form.getAttribute('action'));
        xhr.setRequestHeader('Accept', 'application/json');
        xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
        xhr.setRequestHeader('X-CSRF-Token', config.csrfToken || '');
        xhr.responseType = 'json';
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                bar.style.width = Math.round((e.loaded / e.total) * 100) + '%';
            }
        });
        const done = () => {
            sending = false;
            submit.disabled = false;
            submit.textContent = t('Enviar a revisión');
            progress.hidden = true;
        };
        xhr.addEventListener('load', () => {
            done();
            const payload = xhr.response || {};
            if (xhr.status >= 200 && xhr.status < 300 && payload.ok) {
                window.location.href = payload.redirect;
                return;
            }
            if (xhr.status === 401) {
                window.location.href = (config.baseUrl || '') + '/login.php';
                return;
            }
            showError(payload.error || (xhr.status === 413
                ? t('El archivo supera el tamaño que acepta el servidor.')
                : t('No se pudo enviar la canción. Inténtalo de nuevo.')));
        });
        xhr.addEventListener('error', () => {
            done();
            showError(t('Sin conexión con el servidor. Revisa tu red e inténtalo de nuevo.'));
        });
        sending = true;
        submit.disabled = true;
        submit.textContent = t('Enviando…');
        bar.style.width = '0%';
        progress.hidden = false;
        xhr.send(new FormData(form));
        toast(t('Subiendo tu canción…'), 'info', 2000);
    });
})();
