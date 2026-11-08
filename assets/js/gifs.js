/*
 * TREVIX · GIF y stickers de GIPHY
 * Los botones [data-gif-open] abren #gif-picker, que busca en api/gifs.php (la clave de GIPHY no sale del
 * servidor). Al elegir uno se rellena el campo [data-gif-field] del formulario (gif_id y gif_kind) y el
 * texto deja de ser obligatorio: el comentario o mensaje puede ser solo el GIF.
 */
(function () {
    'use strict';

    const { $, $$ } = window.Trevix;
    const picker = $('#gif-picker');
    if (!picker) {
        return;
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
            preview.alt = gif.title || (gif.kind === 'sticker' ? 'Sticker' : 'GIF');
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
        const params = new URLSearchParams({ kind: kind(), q: q.value.trim(), offset: String(offset) });
        more.hidden = true;
        if (reset) {
            grid.setAttribute('aria-busy', 'true');
            empty.hidden = true;
        }
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
            empty.textContent = q.value.trim() !== '' ? 'No encontramos resultados para «' + q.value.trim() + '».' : 'No hay resultados.';
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
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'gif-picker__item' + (gif.kind === 'sticker' ? ' gif-picker__item--sticker' : '');
        button.setAttribute('aria-label', gif.title || (gif.kind === 'sticker' ? 'Sticker' : 'GIF'));
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
