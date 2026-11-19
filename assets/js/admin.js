/*
 * TREVIX · Panel de administración
 * Drawer móvil, filtro de navegación, confirmaciones y formularios de decisión.
 * Sin JavaScript los formularios se envían directamente y el servidor valida todo.
 */
(function () {
    'use strict';

    const { $, $$, t } = window.Trevix;
    const dialog = $('#confirm-dialog');
    const shell = $('[data-admin]');
    const openBtn = $('[data-admin-open]');
    const backdrop = $('[data-admin-close].admin__backdrop');
    const navFilter = $('[data-admin-nav-filter]');
    const nav = $('[data-admin-nav]');
    let lastFocus = null;

    function setNavOpen(open) {
        if (!shell) {
            return;
        }
        shell.classList.toggle('is-nav-open', open);
        if (backdrop) {
            backdrop.hidden = !open;
        }
        if (openBtn) {
            openBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
        }
        document.documentElement.style.overflow = open ? 'hidden' : '';
        if (open) {
            lastFocus = document.activeElement;
            const closeBtn = $('[data-admin-close].admin__sidebar-close');
            (closeBtn || navFilter)?.focus();
        } else if (lastFocus && typeof lastFocus.focus === 'function') {
            lastFocus.focus();
            lastFocus = null;
        }
    }

    if (shell) {
        document.addEventListener('click', (event) => {
            if (event.target.closest('[data-admin-open]')) {
                setNavOpen(true);
                return;
            }
            if (event.target.closest('[data-admin-close]')) {
                setNavOpen(false);
            }
        });

        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape' && shell.classList.contains('is-nav-open')) {
                setNavOpen(false);
            }
        });

        window.addEventListener('resize', () => {
            if (window.matchMedia('(min-width: 961px)').matches) {
                setNavOpen(false);
            }
        });
    }

    if (navFilter && nav) {
        const filterNav = () => {
            const q = navFilter.value.trim().toLowerCase();
            $$('[data-admin-link]', nav).forEach((link) => {
                const label = link.getAttribute('data-label') || '';
                link.hidden = q !== '' && !label.includes(q);
            });
            $$('[data-admin-group]', nav).forEach((group) => {
                const visible = $$('[data-admin-link]', group).some((link) => !link.hidden);
                group.hidden = !visible;
            });
        };
        navFilter.addEventListener('input', filterNav);
    }

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
