/* OND-ADS: el formulario muestra solo la sección del tipo elegido y el total según los días.
   Sin JavaScript todas las secciones quedan visibles y el servidor usa la del tipo marcado. */
(() => {
    'use strict';

    const form = document.querySelector('[data-ads-form]');
    if (!form) {
        return;
    }
    const daily = Number(form.dataset.dailyCents) || 0;
    const days = form.querySelector('[data-ads-days]');
    const total = form.querySelector('[data-ads-total]');
    const lang = document.documentElement.lang || 'es';

    const money = (cents) => {
        const value = (cents / 100).toLocaleString(lang === 'en' ? 'en-US' : 'es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        return lang === 'en' ? 'US$' + value : 'US$ ' + value;
    };

    const showPanel = () => {
        const kind = form.querySelector('[data-ads-kind]:checked')?.value || 'post';
        form.querySelectorAll('[data-ads-panel]').forEach((panel) => {
            const active = panel.dataset.adsPanel === kind;
            panel.hidden = !active;
            panel.disabled = !active;
        });
    };

    const updateTotal = () => {
        const n = Math.max(0, Math.floor(Number(days?.value) || 0));
        if (!total) {
            return;
        }
        total.hidden = n < 1;
        total.textContent = n > 0 ? '· Total: ' + money(daily * n) : '';
    };

    form.addEventListener('change', (event) => {
        if (event.target.matches('[data-ads-kind]')) {
            showPanel();
        }
    });
    days?.addEventListener('input', updateTotal);
    showPanel();
    updateTotal();
})();
