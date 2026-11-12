/*
 * TREVIX · @menciones en comentarios y respuestas
 * En cualquier campo con [data-mention-input], al escribir «@» se muestran tus amistades, cuentas que sigues y
 * seguidores; al seguir escribiendo se filtran y se suman otras personas de TREVIX. Flechas + Enter/Tab o un toque
 * eligen a la persona. El texto final es «@usuario »: el servidor detecta la mención y avisa a esa persona.
 */
(function () {
    'use strict';

    const { $$, api, t } = window.Trevix;
    const TOKEN = /(^|\s)@([\p{L}\p{N}._]{0,30})$/u;

    function attach(input) {
        if (input.dataset.mentionBound) {
            return;
        }
        input.dataset.mentionBound = '1';
        const host = input.parentElement;
        host.classList.add('mention-host');
        const list = document.createElement('ul');
        list.className = 'mention-suggest';
        list.setAttribute('role', 'listbox');
        list.setAttribute('aria-label', t('Sugerencias de menciones'));
        list.hidden = true;
        input.insertAdjacentElement('afterend', list);

        let timer = null;
        let request = 0;
        let index = -1;

        const query = () => {
            const match = input.value.slice(0, input.selectionStart).match(TOKEN);
            return match ? match[2] : null;
        };

        const hide = () => {
            list.hidden = true;
            list.replaceChildren();
            index = -1;
        };

        const highlight = (next) => {
            const items = Array.from(list.children);
            index = items.length ? (next + items.length) % items.length : -1;
            items.forEach((item, i) => item.setAttribute('aria-selected', i === index ? 'true' : 'false'));
        };

        const insert = (username) => {
            const caret = input.selectionStart;
            const before = input.value.slice(0, caret).replace(/@([\p{L}\p{N}._]{0,30})$/u, '@' + username + ' ');
            input.value = before + input.value.slice(caret);
            input.setSelectionRange(before.length, before.length);
            hide();
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.focus();
        };

        const suggest = async () => {
            const q = query();
            if (q === null) {
                hide();
                return;
            }
            const id = ++request;
            try {
                const data = await api('api/mentions.php?q=' + encodeURIComponent(q));
                if (id !== request || query() !== q) {
                    return;
                }
                list.replaceChildren();
                data.items.forEach((user) => {
                    const li = document.createElement('li');
                    li.setAttribute('role', 'option');
                    li.className = 'mention-suggest__item';
                    li.dataset.username = user.username;
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
                    if (user.relation) {
                        const tag = document.createElement('small');
                        tag.className = 'mention-suggest__tag';
                        tag.textContent = user.relation;
                        li.appendChild(tag);
                    }
                    li.addEventListener('mousedown', (event) => {
                        event.preventDefault();
                        insert(user.username);
                    });
                    list.appendChild(li);
                });
                list.hidden = data.items.length === 0;
                highlight(0);
            } catch {
                hide();
            }
        };

        input.addEventListener('input', (event) => {
            if (!event.isTrusted) {
                return;
            }
            window.clearTimeout(timer);
            timer = window.setTimeout(suggest, query() === '' ? 0 : 200);
        });
        input.addEventListener('keydown', (event) => {
            if (list.hidden) {
                return;
            }
            if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                event.preventDefault();
                highlight(index + (event.key === 'ArrowDown' ? 1 : -1));
            } else if (event.key === 'Enter' || event.key === 'Tab') {
                const item = list.children[index];
                if (item) {
                    event.preventDefault();
                    insert(item.dataset.username);
                }
            } else if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                hide();
            }
        });
        input.addEventListener('blur', () => window.setTimeout(hide, 150));
    }

    function bind(root = document) {
        $$('[data-mention-input]', root).forEach(attach);
    }

    bind();
    Object.assign(window.Trevix, { bindMentions: bind });
})();
