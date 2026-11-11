/*
 * TREVIX · Comunidades
 * Unirse, pedir acceso y salir desde las tarjetas sin recargar la página. En la página de la comunidad
 * el formulario se envía de forma normal (cambian las pestañas y el contenido visible) y solo se
 * añade la confirmación. Todo funciona igual sin JavaScript.
 */
(function () {
    'use strict';

    const { $, toast, t } = window.Trevix;
    const busy = new WeakSet();

    async function confirmed(form) {
        const message = form.getAttribute('data-join-confirm');
        if (!message) {
            return true;
        }
        const ask = window.Trevix.confirmAction || ((text) => Promise.resolve(window.confirm(text)));
        return ask(message, form.getAttribute('data-join-confirm-label') || t('Confirmar'));
    }

    document.addEventListener('submit', async (event) => {
        const form = event.target;
        if (!form.matches('[data-community-join]') || form.dataset.confirmed) {
            return;
        }
        event.preventDefault();
        if (busy.has(form) || !(await confirmed(form))) {
            return;
        }

        if (form.closest('.community-hero')) {
            form.dataset.confirmed = '1';
            form.submit();
            return;
        }

        busy.add(form);
        const button = $('button[type="submit"]', form);
        button.disabled = true;
        try {
            const result = await window.Trevix.postForm(form);
            const box = form.closest('[data-community-join-box]');
            const holder = document.createElement('div');
            holder.innerHTML = result.html;
            if (box && holder.firstElementChild) {
                box.replaceWith(holder.firstElementChild);
            }
            const id = $('input[name="community_id"]', form).value;
            const members = Number(result.members) || 0;
            document.querySelectorAll('[data-community-members="' + id + '"]').forEach((el) => {
                el.textContent = window.Trevix.compactNumber(members);
            });
            document.querySelectorAll('[data-community-members-label="' + id + '"]').forEach((el) => {
                el.textContent = members === 1 ? t('miembro') : t('miembros');
            });
            toast(result.message, 'success');
        } catch (error) {
            button.disabled = false;
            toast(error.message, 'error');
        } finally {
            busy.delete(form);
        }
    });

    document.addEventListener('change', (event) => {
        const select = event.target;
        if (select.matches('select[data-autosubmit]') && select.form) {
            select.form.submit();
        }
    });
})();
