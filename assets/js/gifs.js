/*
 * TREVIX · GIF y stickers de GIPHY
 * Los botones [data-gif-open] abren #gif-picker, que busca en api/gifs.php (la clave de GIPHY no sale del
 * servidor). Al elegir uno se rellena el campo [data-gif-field] del formulario (gif_id y gif_kind) y el
 * texto deja de ser obligatorio: el comentario o mensaje puede ser solo el GIF.
 * La estrella de cada resultado lo guarda en «Favoritos» (pestaña propia, máx. 100 por cuenta).
 */
(function () {
    'use strict';

    const { $, $$, t, toast } = window.Trevix;
    const picker = $('#gif-picker');
    if (!picker) {
        return;
    }
    const favoritesUrl = picker.getAttribute('data-gif-favorites');
    let favorites = null;

    async function loadFavorites() {
        if (favorites === null && favoritesUrl) {
            const data = await window.Trevix.api('api/messages.php?action=stickers');
            favorites = data.items || [];
            $$('.gif-picker__fav', grid).forEach((star) => {
                star.setAttribute('aria-pressed', isFavorite(star.getAttribute('data-id')) ? 'true' : 'false');
            });
        }
        return favorites || [];
    }

    const isFavorite = (id) => Boolean(favorites && favorites.some((f) => f.id === id));

    async function toggleFavorite(gif, star) {
        const save = !isFavorite(gif.id);
        const data = new FormData();
        data.append('action', 'sticker_favorite');
        data.append('gif_id', gif.id);
        data.append('gif_kind', gif.kind);
        data.append('save', save ? '1' : '0');
        star.disabled = true;
        try {
            const result = await window.Trevix.api('api/messages.php', { method: 'POST', data });
            favorites = result.items || [];
            star.setAttribute('aria-pressed', save ? 'true' : 'false');
            toast(save ? t('Guardado en favoritos.') : t('Quitado de favoritos.'), 'success');
            if (!save && kind() === 'favorites') {
                star.closest('.gif-picker__cell').remove();
                empty.hidden = grid.children.length > 0;
                empty.textContent = t('Toca la estrella de un sticker o GIF para guardarlo aquí.');
            }
        } catch (error) {
            toast(error.message, 'error');
        } finally {
            star.disabled = false;
        }
    }

    const q = $('[data-gif-q]', picker);
    const grid = $('[data-gif-results]', picker);
    const empty = $('[data-gif-empty]', picker);
    const more = $('[data-gif-more]', picker);
    let targetField = null;
    let offset = 0;
    let requestId = 0;
    let timer = null;

    function kind() {
        const checked = $('[data-gif-kind]:checked', picker);
        return checked ? checked.value : 'gif';
    }

    /** Textarea del formulario: obligatorio solo si no hay GIF. */
    function bodyInput(field) {
        const form = field.closest('form');
        return form ? $('textarea[name="body"]', form) : null;
    }

    function setField(field, gif) {
        $('[data-gif-id]', field).value = gif ? gif.id : '';
        $('[data-gif-kind-input]', field).value = gif ? gif.kind : 'gif';
        const selected = $('[data-gif-selected]', field);
        const preview = $('[data-gif-preview]', field);
        if (gif) {
            preview.src = gif.preview || gif.url;
            preview.alt = gif.title || (gif.kind === 'sticker' ? t('Sticker') : 'GIF');
        } else {
            preview.removeAttribute('src');
        }
        selected.hidden = !gif;
        const body = bodyInput(field);
        if (body) {
            if (gif && body.required) {
                body.dataset.gifRequired = '1';
                body.required = false;
            } else if (!gif && body.dataset.gifRequired) {
                body.required = true;
                delete body.dataset.gifRequired;
            }
        }
        field.dispatchEvent(new CustomEvent('trevix:gif-change', { bubbles: true, detail: { gif } }));
    }

    function clearField(field) {
        if (field && $('[data-gif-id]', field).value !== '') {
            setField(field, null);
        }
    }

    window.Trevix.gifs = { clearField, hasGif: (field) => Boolean(field && $('[data-gif-id]', field).value) };

    async function search(reset) {
        if (reset) {
            offset = 0;
        }
        const id = ++requestId;
        more.hidden = true;
        if (reset) {
            grid.setAttribute('aria-busy', 'true');
            empty.hidden = true;
        }
        if (kind() === 'favorites') {
            q.closest('.input-wrap').hidden = true;
            try {
                const items = await loadFavorites();
                if (id !== requestId) {
                    return;
                }
                grid.replaceChildren();
                items.forEach((gif) => grid.appendChild(item(Object.assign({ preview: gif.url }, gif))));
                empty.hidden = items.length > 0;
                empty.textContent = t('Toca la estrella de un sticker o GIF para guardarlo aquí.');
            } catch (error) {
                empty.hidden = false;
                empty.textContent = error.message;
            } finally {
                grid.removeAttribute('aria-busy');
            }
            return;
        }
        q.closest('.input-wrap').hidden = false;
        loadFavorites().catch(() => {});
        const params = new URLSearchParams({ kind: kind(), q: q.value.trim(), offset: String(offset) });
        try {
            const data = await window.Trevix.api('api/gifs.php?' + params.toString());
            if (id !== requestId) {
                return;
            }
            if (reset) {
                grid.replaceChildren();
            }
            data.items.forEach((gif) => grid.appendChild(item(gif)));
            empty.hidden = grid.children.length > 0;
            empty.textContent = q.value.trim() !== '' ? t('No encontramos resultados para «{q}».', { q: q.value.trim() }) : t('No hay resultados.');
            if (data.next !== null) {
                offset = data.next;
                more.hidden = false;
            }
        } catch (error) {
            if (id === requestId) {
                empty.hidden = false;
                empty.textContent = error.message;
            }
        } finally {
            grid.removeAttribute('aria-busy');
        }
    }

    function item(gif) {
        const cell = document.createElement('div');
        cell.className = 'gif-picker__cell';
        cell.appendChild(choice(gif));
        if (favoritesUrl) {
            const star = document.createElement('button');
            star.type = 'button';
            star.className = 'gif-picker__fav';
            star.textContent = '★';
            star.setAttribute('data-id', gif.id);
            star.setAttribute('aria-label', t('Guardar en favoritos'));
            star.setAttribute('aria-pressed', isFavorite(gif.id) ? 'true' : 'false');
            star.addEventListener('click', (event) => {
                event.stopPropagation();
                toggleFavorite(gif, star);
            });
            cell.appendChild(star);
        }
        return cell;
    }

    function choice(gif) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'gif-picker__item' + (gif.kind === 'sticker' ? ' gif-picker__item--sticker' : '');
        button.setAttribute('aria-label', gif.title || (gif.kind === 'sticker' ? t('Sticker') : 'GIF'));
        const img = document.createElement('img');
        img.src = gif.preview;
        img.alt = '';
        img.loading = 'lazy';
        img.referrerPolicy = 'no-referrer';
        button.appendChild(img);
        button.addEventListener('click', () => {
            if (targetField) {
                setField(targetField, gif);
                const body = bodyInput(targetField);
                picker.close();
                if (body) {
                    body.focus();
                }
            }
        });
        return button;
    }

    let loadedKind = null;

    document.addEventListener('click', (event) => {
        const remove = event.target.closest('[data-gif-remove]');
        if (remove) {
            const field = remove.closest('[data-gif-field]');
            if (field) {
                setField(field, null);
            }
            return;
        }
        const open = event.target.closest('[data-gif-open]');
        if (!open) {
            return;
        }
        const form = open.closest('form');
        const field = form ? $('[data-gif-field]', form) : null;
        if (!field) {
            return;
        }
        event.preventDefault();
        targetField = field;
        if (!picker.open) {
            picker.showModal();
        }
        if (loadedKind !== kind()) {
            loadedKind = kind();
            search(true);
        }
        q.focus();
    });

    /* Al enviar un comentario o mensaje con recarga, o al vaciar el formulario, se quita el GIF. */
    document.addEventListener('reset', (event) => {
        const field = event.target instanceof HTMLFormElement ? $('[data-gif-field]', event.target) : null;
        if (field) {
            setField(field, null);
        }
    }, true);

    q.addEventListener('input', () => {
        window.clearTimeout(timer);
        timer = window.setTimeout(() => search(true), 350);
    });
    $$('[data-gif-kind]', picker).forEach((radio) => radio.addEventListener('change', () => {
        loadedKind = kind();
        search(true);
    }));
    more.addEventListener('click', () => search(false));
    picker.addEventListener('close', () => {
        targetField = null;
    });
})();
