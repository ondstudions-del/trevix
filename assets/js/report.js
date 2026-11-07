/*
 * TREVIX · Reportes
 * Los enlaces [data-report] abren un diálogo y el reporte se envía con fetch al mismo endpoint
 * que usa report.php. Sin JavaScript (o sin <dialog>) el enlace lleva al formulario completo.
 */
(function () {
    'use strict';

    const { $, toast } = window.Trevix;
    const dialog = $('#report-dialog');
    if (!dialog || typeof dialog.showModal !== 'function') {
        return;
    }
    const form = $('[data-report-form]', dialog);
    const errorBox = $('[data-report-error]', dialog);
    const submit = $('button[type="submit"]', form);
    let busy = false;

    function showError(message) {
        errorBox.textContent = message;
        errorBox.hidden = !message;
    }

    function open(link) {
        form.reset();
        showError('');
        $('[data-report-type]', form).value = link.getAttribute('data-report');
        $('[data-report-id]', form).value = link.getAttribute('data-report-id');
        $('[data-report-target]', dialog).textContent = 'Vas a reportar ' + (link.getAttribute('data-report-label') || 'este contenido') + '.';
        if (window.Trevix.closeDropdowns) {
            window.Trevix.closeDropdowns();
        }
        dialog.showModal();
        const first = $('input[name="reason"]', form);
        if (first) {
            first.focus();
        }
    }

    document.addEventListener('click', (event) => {
        const link = event.target.closest('a[data-report]');
        if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) {
            return;
        }
        event.preventDefault();
        open(link);
    });

    dialog.addEventListener('click', (event) => {
        if (event.target.closest('[data-report-close]') || event.target === dialog) {
            dialog.close();
        }
    });

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (busy) {
            return;
        }
        const reason = $('input[name="reason"]:checked', form);
        const details = $('textarea[name="details"]', form).value.trim();
        if (!reason) {
            showError('Elige el motivo del reporte.');
            return;
        }
        if (reason.value === 'other' && details.length < 5) {
            showError('Cuéntanos brevemente qué ocurre.');
            return;
        }
        busy = true;
        submit.disabled = true;
        submit.setAttribute('aria-busy', 'true');
        showError('');
        try {
            const response = await fetch(form.getAttribute('action'), {
                method: 'POST',
                body: new FormData(form),
                headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
                credentials: 'same-origin',
            });
            const payload = await response.json().catch(() => ({}));
            if (!response.ok || !payload.ok) {
                throw new Error(payload.error || 'No se pudo enviar el reporte. Inténtalo de nuevo.');
            }
            dialog.close();
            toast(payload.message, 'success', 4000);
        } catch (error) {
            showError(error.message);
        } finally {
            busy = false;
            submit.disabled = false;
            submit.removeAttribute('aria-busy');
        }
    });
})();
