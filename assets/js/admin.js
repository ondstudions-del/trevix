/*
 * TREVIX · Panel de administración
 * Confirmación de acciones con el diálogo propio y campos que dependen de la medida elegida.
 * Sin JavaScript los formularios se envían directamente y el servidor valida todo.
 */
(function () {
    'use strict';

    const { $, $$, t } = window.Trevix;
    const dialog = $('#confirm-dialog');

    function confirmAction(message, label) {
        if (!dialog || typeof dialog.showModal !== 'function') {
            return Promise.resolve(window.confirm(message));
        }
        $('[data-confirm-text]', dialog).textContent = message;
        $('[data-confirm-ok]', dialog).textContent = label || t('Confirmar');
        dialog.returnValue = '';
        dialog.showModal();
        return new Promise((resolve) => {
            dialog.addEventListener('close', () => resolve(dialog.returnValue === 'ok'), { once: true });
        });
    }

    document.addEventListener('submit', async (event) => {
        const form = event.target;
        if (!form.matches('[data-confirm]') || form.dataset.confirmed) {
            return;
        }
        event.preventDefault();
        if (await confirmAction(form.getAttribute('data-confirm'), form.getAttribute('data-confirm-label'))) {
            form.dataset.confirmed = '1';
            const submit = $('button[type="submit"]', form);
            if (submit) {
                submit.disabled = true;
                submit.setAttribute('aria-busy', 'true');
            }
            form.submit();
        }
    });

    /* Decisión sobre un reporte: la duración solo aplica a la suspensión y algunas medidas exigen motivo. */
    $$('.decision__form').forEach((form) => {
        const radios = $$('input[name="measure"]', form);
        const note = $('textarea[name="note"]', form);
        if (radios.length === 0) {
            return;
        }
        const sync = () => {
            const checked = radios.find((radio) => radio.checked);
            const measure = checked ? checked.value : 'none';
            $$('[data-show-for]', form).forEach((field) => {
                field.hidden = field.getAttribute('data-show-for') !== measure;
            });
            if (note) {
                const required = Boolean(checked && checked.hasAttribute('data-needs-reason'));
                note.required = required;
                note.minLength = required ? 5 : 0;
            }
        };
        radios.forEach((radio) => radio.addEventListener('change', sync));
        sync();
    });

    /* Mostrar u ocultar la contraseña nueva al editar una cuenta. */
    document.addEventListener('click', (event) => {
        const button = event.target.closest('[data-toggle-password]');
        if (!button) {
            return;
        }
        const input = button.parentElement.querySelector('input');
        const visible = input.type === 'password';
        input.type = visible ? 'text' : 'password';
        button.setAttribute('aria-pressed', String(visible));
        button.setAttribute('aria-label', visible ? t('Ocultar contraseña') : t('Mostrar contraseña'));
    });

    /* Cierra los menús desplegables <details> al hacer clic fuera. */
    document.addEventListener('click', (event) => {
        $$('details.admin-menu[open]').forEach((menu) => {
            if (!menu.contains(event.target)) {
                menu.open = false;
            }
        });
    });
})();
