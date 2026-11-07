/*
 * TREVIX · Seguir, solicitudes de seguimiento
 * Los botones Seguir / Siguiendo / Solicitud enviada y Aceptar / Rechazar son formularios reales;
 * aquí se envían con fetch y se actualizan todos los de la misma persona en la página.
 * Sin JavaScript funcionan igual, con recarga de página.
 */
(function () {
    'use strict';

    const { $, $$, toast, postForm, confirmAction, compactNumber } = window.Trevix;
    const ACTIONS = { none: 'follow', following: 'unfollow', requested: 'cancel' };
    const busy = new WeakSet();

    function applyState(userId, state, followersCount) {
        $$('[data-follow-form][data-user-id="' + userId + '"]').forEach((form) => {
            const button = $('button[type="submit"]', form);
            const idle = form.dataset.idleClass || 'btn--primary';
            form.dataset.state = state;
            $('input[name="action"]', form).value = ACTIONS[state];
            button.textContent = form.getAttribute('data-label-' + state);
            button.setAttribute('aria-pressed', String(state !== 'none'));
            button.classList.toggle(idle, state === 'none');
            button.classList.toggle('btn--secondary', state !== 'none');
        });

        $$('[data-follow-menu][data-user-id="' + userId + '"]').forEach((form) => {
            const handle = '@' + form.dataset.username;
            const labels = { none: 'Seguir a ', following: 'Dejar de seguir a ', requested: 'Cancelar solicitud a ' };
            $('input[name="action"]', form).value = ACTIONS[state];
            $('[data-follow-label]', form).textContent = labels[state] + handle;
            $$('[data-follow-icon]', form).forEach((icon) => {
                icon.hidden = icon.dataset.followIcon !== (state === 'none' ? 'none' : 'active');
            });
        });

        if (typeof followersCount === 'number') {
            $$('[data-followers-count="' + userId + '"]').forEach((el) => {
                el.textContent = compactNumber(followersCount);
            });
        }
    }

    async function submitFollow(form) {
        if (busy.has(form)) {
            return;
        }
        const userId = form.dataset.userId;
        const action = $('input[name="action"]', form).value;

        if (action === 'unfollow' && form.dataset.private === '1') {
            window.Trevix.closeDropdowns();
            const ok = await confirmAction(
                '@' + form.dataset.username + ' tiene la cuenta privada. Si dejas de seguirla, tendrás que enviar otra solicitud para ver sus publicaciones.',
                'Dejar de seguir'
            );
            if (!ok) {
                return;
            }
        }

        busy.add(form);
        form.classList.add('is-busy');
        try {
            const result = await postForm(form);
            applyState(userId, result.state, result.followers_count);
            window.Trevix.closeDropdowns();
            toast(result.message, 'success', 2400);
            // En un perfil privado, seguir o dejar de seguir cambia lo que se puede ver.
            if ($('[data-reload-on-follow="' + userId + '"]')) {
                window.location.reload();
            }
        } catch (error) {
            toast(error.message, 'error');
        } finally {
            busy.delete(form);
            form.classList.remove('is-busy');
        }
    }

    function decrementRequestBadges() {
        $$('a[href*="notifications.php"] .badge-count').forEach((badge) => {
            const value = parseInt(badge.textContent, 10);
            if (Number.isNaN(value) || badge.textContent.includes('+')) {
                return;
            }
            if (value <= 1) {
                badge.remove();
            } else {
                badge.textContent = String(value - 1);
                badge.setAttribute('aria-label', (value - 1) + ' sin leer');
            }
        });
    }

    async function submitRequest(form) {
        const box = form.closest('[data-request-actions]');
        if (!box || box.dataset.busy) {
            return;
        }
        box.dataset.busy = '1';
        $$('button', box).forEach((button) => { button.disabled = true; });
        try {
            const result = await postForm(form);
            const note = document.createElement('p');
            note.className = 'notif__result';
            note.textContent = result.message;
            box.replaceWith(note);
            decrementRequestBadges();
        } catch (error) {
            delete box.dataset.busy;
            $$('button', box).forEach((button) => { button.disabled = false; });
            toast(error.message, 'error');
        }
    }

    document.addEventListener('submit', (event) => {
        const form = event.target;
        if (form.matches('[data-follow-form], [data-follow-menu]')) {
            event.preventDefault();
            submitFollow(form);
        } else if (form.matches('[data-request-form]')) {
            event.preventDefault();
            submitRequest(form);
        }
    });
})();
