/*
 * TREVIX · Formularios de cuenta
 * Validación en el cliente para dar respuesta inmediata. No sustituye a la validación
 * del servidor, que se aplica siempre en los controladores.
 */
(function () {
    'use strict';

    const { $, $$ } = window.Trevix;
    const USERNAME = /^[a-z0-9_.]{3,30}$/;
    const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
    const MIN_AGE = 13;

    /* Mostrar u ocultar contraseña */
    document.addEventListener('click', (event) => {
        const button = event.target.closest('[data-toggle-password]');
        if (!button) {
            return;
        }
        const input = button.parentElement.querySelector('input');
        const visible = input.type === 'password';
        input.type = visible ? 'text' : 'password';
        button.setAttribute('aria-pressed', String(visible));
        button.setAttribute('aria-label', visible ? 'Ocultar contraseña' : 'Mostrar contraseña');
    });

    /* Fortaleza de la contraseña */
    function passwordChecks(value, min) {
        return {
            length: [...value].length >= min,
            case: /\p{Ll}/u.test(value) && /\p{Lu}/u.test(value),
            number: /\d/.test(value),
            symbol: /[^\p{L}\d]/u.test(value),
        };
    }

    const LEVELS = ['Escribe una contraseña', 'Muy débil', 'Débil', 'Buena', 'Muy segura'];

    function updateStrength(input) {
        const meter = document.querySelector(input.getAttribute('data-strength-meter'));
        const min = Number(input.getAttribute('minlength')) || 10;
        const checks = passwordChecks(input.value, min);
        const passed = Object.values(checks).filter(Boolean).length;
        const level = input.value === '' ? 0 : Math.max(1, checks.length ? passed : Math.min(passed, 1));

        if (meter) {
            meter.dataset.level = String(level);
            $('.strength__label', meter).textContent = LEVELS[level];
        }
        const list = document.querySelector('[data-requirements-for="' + input.id + '"]');
        if (list) {
            Object.entries(checks).forEach(([key, met]) => {
                const item = $('[data-req="' + key + '"]', list);
                if (item) {
                    item.classList.toggle('is-met', met);
                }
            });
        }
        return checks;
    }

    /* Reglas de validación */
    function ageFrom(dateValue) {
        const birth = new Date(dateValue + 'T00:00:00');
        if (Number.isNaN(birth.getTime())) {
            return -1;
        }
        const today = new Date();
        let age = today.getFullYear() - birth.getFullYear();
        const monthDiff = today.getMonth() - birth.getMonth();
        if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
            age -= 1;
        }
        return age;
    }

    function validate(input) {
        if (input.closest('[hidden]')) {
            return '';
        }
        const value = input.type === 'checkbox' ? input.checked : input.value.trim();
        switch (input.getAttribute('data-rule')) {
            case 'required':
                return value ? '' : 'Este campo es obligatorio.';
            case 'name':
                if (!value) return 'Escribe tu nombre.';
                return value.length < 2 ? 'El nombre debe tener al menos 2 caracteres.' : '';
            case 'username':
                if (!value) return 'Elige un nombre de usuario.';
                return USERNAME.test(value) ? '' : 'Usa de 3 a 30 caracteres: minúsculas, números, punto o guion bajo.';
            case 'email':
                if (!value) return 'Escribe tu correo electrónico.';
                return EMAIL.test(value) ? '' : 'Escribe un correo electrónico válido.';
            case 'birthdate': {
                if (!value) return 'Indica tu fecha de nacimiento.';
                const age = ageFrom(value);
                if (age < 0 || age > 120) return 'La fecha no es válida.';
                return age < MIN_AGE ? 'Debes tener al menos ' + MIN_AGE + ' años para usar TREVIX.' : '';
            }
            case 'password': {
                if (!input.value) return 'Crea una contraseña.';
                const checks = updateStrength(input);
                if (!checks.length) return 'La contraseña es demasiado corta.';
                return Object.values(checks).every(Boolean) ? '' : 'Cumple todos los requisitos: mayúsculas, minúsculas, un número y un símbolo.';
            }
            case 'confirm': {
                const original = document.querySelector(input.getAttribute('data-confirm'));
                if (!input.value) return 'Confirma la contraseña.';
                return original && original.value === input.value ? '' : 'Las contraseñas no coinciden.';
            }
            case 'terms':
                return value ? '' : 'Debes aceptar los términos para continuar.';
            default:
                return '';
        }
    }

    function showResult(input, message) {
        const box = document.querySelector('[data-error-for="' + input.id + '"]');
        input.setAttribute('aria-invalid', message ? 'true' : 'false');
        if (box) {
            box.id = box.id || 'error-' + input.id;
            box.textContent = message;
            box.hidden = !message;
            if (message) {
                input.setAttribute('aria-describedby', box.id);
            } else {
                input.removeAttribute('aria-describedby');
            }
        }
    }

    /* El cambio de correo exige la contraseña actual: el campo aparece solo si el correo cambia */
    $$('[data-original]').forEach((input) => {
        const box = input.form && $('[data-email-password]', input.form);
        if (!box) {
            return;
        }
        const sync = () => {
            const changed = input.value.trim().toLowerCase() !== input.getAttribute('data-original').toLowerCase();
            box.hidden = !changed && !box.querySelector('[aria-invalid="true"]');
        };
        input.addEventListener('input', sync);
        sync();
    });

    $$('form[data-validate]').forEach((form) => {
        const fields = $$('[data-rule]', form);

        fields.forEach((input) => {
            const eventName = input.type === 'checkbox' ? 'change' : 'blur';
            input.addEventListener(eventName, () => {
                input.dataset.touched = 'true';
                showResult(input, validate(input));
            });
            input.addEventListener('input', () => {
                if (input.matches('[data-strength-meter]')) {
                    updateStrength(input);
                }
                if (input.dataset.touched) {
                    showResult(input, validate(input));
                }
                const dependent = form.querySelector('[data-confirm="#' + input.id + '"]');
                if (dependent && dependent.dataset.touched) {
                    showResult(dependent, validate(dependent));
                }
            });
        });

        form.addEventListener('submit', (event) => {
            let firstInvalid = null;
            fields.forEach((input) => {
                input.dataset.touched = 'true';
                const message = validate(input);
                showResult(input, message);
                if (message && !firstInvalid) {
                    firstInvalid = input;
                }
            });
            if (firstInvalid) {
                event.preventDefault();
                firstInvalid.focus();
            }
        });
    });
})();
