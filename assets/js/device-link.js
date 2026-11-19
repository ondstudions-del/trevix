/*
 * TREVIX · VINCRIPTAR (web)
 * QR estándar + código legible; poll JSON sin recargar la página.
 */
(function () {
    'use strict';

    const root = document.getElementById('device-link-root');
    const bootEl = document.getElementById('device-link-boot');
    if (!root || !bootEl || !window.TrevixVincriptar) {
        return;
    }

    let boot;
    try {
        boot = JSON.parse(bootEl.textContent || '{}');
    } catch {
        return;
    }

    const { toast } = window.Trevix || { toast() {} };
    const i18n = boot.i18n || {};
    const ttlTotal = Number(boot.ttl) || 60;
    const V = window.TrevixVincriptar;

    document.querySelectorAll('[data-copy-code]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            const code = btn.getAttribute('data-code') || '';
            try {
                await navigator.clipboard.writeText(V.normalize(code));
                toast(i18n.copied || 'Código copiado.', 'success');
                btn.classList.add('is-copied');
                setTimeout(() => btn.classList.remove('is-copied'), 1200);
            } catch {
                /* ignore */
            }
        });
    });

    const ttlLabel = root.querySelector('[data-link-ttl-label]');
    const ttlBar = root.querySelector('[data-link-ttl-bar]');
    const expiresAt = boot.expires_at ? Date.parse(String(boot.expires_at).replace(' ', 'T')) : NaN;

    function tickTtl() {
        if (!ttlLabel || Number.isNaN(expiresAt)) {
            return;
        }
        const left = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000));
        if (left <= 0) {
            ttlLabel.textContent = i18n.expired || 'Caducado';
            if (ttlBar) {
                ttlBar.style.transform = 'scaleX(0)';
            }
            return;
        }
        ttlLabel.textContent = (i18n.expires || 'Caduca en {n} s').replace('{n}', String(left));
        if (ttlBar) {
            ttlBar.style.transform = 'scaleX(' + Math.min(1, left / ttlTotal) + ')';
        }
    }
    tickTtl();
    setInterval(tickTtl, 1000);

    const phase = boot.phase || '';

    function showGuestClaimed() {
        root.dataset.phase = 'guest-waiting';
        const badge = root.querySelector('[data-link-badge]');
        if (badge) {
            badge.textContent = i18n.confirm || 'Confirmar';
            badge.classList.add('link-chip--pulse');
        }
        const claim = root.querySelector('[data-link-claim-panel]');
        const waitScan = root.querySelector('[data-link-wait-scan]');
        if (claim) {
            claim.hidden = false;
        }
        if (waitScan) {
            waitScan.hidden = true;
        }
    }

    function startGuestPoll() {
        const statusUrl = boot.status_url || '';
        const completeUrl = boot.complete_url || window.location.href;
        if (!statusUrl || !boot.code) {
            return;
        }
        const ms = Math.max(2000, Number(boot.poll_ms) || 3000);
        let inFlight = false;
        let done = false;

        async function tick() {
            if (done) {
                return;
            }
            if (document.hidden || inFlight) {
                setTimeout(tick, ms);
                return;
            }
            inFlight = true;
            try {
                const res = await fetch(statusUrl, {
                    credentials: 'same-origin',
                    headers: { Accept: 'application/json' },
                });
                if (res.ok) {
                    const body = await res.json();
                    const data = body && body.data ? body.data : body;
                    const status = data && data.status ? String(data.status) : '';
                    if (status === 'claimed' && root.dataset.phase === 'guest-show') {
                        showGuestClaimed();
                    } else if (status === 'approved') {
                        done = true;
                        window.location.assign(completeUrl);
                        return;
                    } else if (status === 'expired' || status === 'cancelled') {
                        done = true;
                        window.location.assign(completeUrl);
                        return;
                    }
                }
            } catch {
                /* retry */
            } finally {
                inFlight = false;
            }
            setTimeout(tick, ms);
        }
        setTimeout(tick, ms);
    }

    if (phase === 'guest-show' || phase === 'guest-waiting') {
        startGuestPoll();
    }

    const qrCanvas = document.getElementById('vincriptar-qr-canvas');
    if (qrCanvas && boot.code && (phase === 'guest-show' || phase === 'guest-waiting')) {
        const paint = () => V.renderCanvas(qrCanvas, boot.code, { size: 280 });
        paint();
        window.addEventListener('resize', paint);
    }

    const video = document.getElementById('vincriptar-video');
    const scanCanvas = document.getElementById('vincriptar-scan-canvas');
    const hint = root.querySelector('[data-scan-hint]');
    const codeInput = document.getElementById('code');
    let stream;
    let scanning = false;
    let lastTried = '';

    async function startCamera() {
        if (!video || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            if (hint) {
                hint.textContent = i18n.manual || 'Introducir código';
            }
            return;
        }
        try {
            stream = await navigator.mediaDevices.getUserMedia({
                audio: false,
                video: { facingMode: { ideal: 'environment' }, width: { ideal: 720 }, height: { ideal: 720 } },
            });
            video.srcObject = stream;
            await video.play();
            scanning = true;
            requestAnimationFrame(scanLoop);
        } catch {
            if (hint) {
                hint.textContent = i18n.manual || 'Introducir código';
            }
        }
    }

    function scanLoop() {
        if (!scanning || !video || !scanCanvas || video.readyState < 2) {
            if (scanning) {
                requestAnimationFrame(scanLoop);
            }
            return;
        }
        const w = video.videoWidth;
        const h = video.videoHeight;
        if (w && h) {
            const side = Math.min(w, h);
            const sx = (w - side) / 2;
            const sy = (h - side) / 2;
            scanCanvas.width = 360;
            scanCanvas.height = 360;
            const ctx = scanCanvas.getContext('2d', { willReadFrequently: true });
            ctx.drawImage(video, sx, sy, side, side, 0, 0, 360, 360);
            const code = V.decodeImageData(ctx.getImageData(0, 0, 360, 360));
            if (code && code !== lastTried && codeInput) {
                lastTried = code;
                codeInput.value = code;
                scanning = false;
                stopCamera();
                codeInput.form && codeInput.form.requestSubmit();
                return;
            }
        }
        requestAnimationFrame(scanLoop);
    }

    function stopCamera() {
        scanning = false;
        if (stream) {
            stream.getTracks().forEach((t) => t.stop());
            stream = null;
        }
    }

    if (phase === 'host-scan') {
        startCamera();
    }

    window.addEventListener('beforeunload', () => {
        stopCamera();
    });
})();