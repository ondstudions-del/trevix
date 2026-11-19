/*
 * TREVIX · VINCRIPTAR — código seguro + QR estándar (lectura con jsQR).
 */
(function (global) {
    'use strict';

    const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    function normalize(raw) {
        let s = String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
        s = s.replace(/O/g, '0').replace(/[IL]/g, '1').replace(/U/g, 'V');
        return s;
    }

    function payloadFor(code) {
        return 'trevix://vincriptar/' + normalize(code);
    }

    function formatDisplay(code) {
        const c = normalize(code);
        if (c.length === 8) {
            return c.slice(0, 4) + '-' + c.slice(4);
        }
        return c;
    }

    function parsePayload(text) {
        const t = String(text || '').trim();
        if (!t) {
            return null;
        }
        let m = t.match(/trevix:\/\/vincriptar\/([A-Z0-9]{6,12})/i)
            || t.match(/trevix:\/\/vincode\/([A-Z0-9]{6,12})/i);
        if (m) {
            return normalize(m[1]);
        }
        m = t.match(/\b([0-9A-Z]{8})\b/);
        return m ? normalize(m[1]) : null;
    }

    function renderCanvas(canvas, code, opts) {
        if (!canvas || !global.qrcodegen || !code) {
            return;
        }
        const options = opts || {};
        const qr = qrcodegen.QrCode.encodeText(payloadFor(code), qrcodegen.QrCode.Ecc.MEDIUM);
        const border = options.border == null ? 2 : Number(options.border);
        const size = qr.size + border * 2;
        const px = Math.max(200, Number(options.size) || Math.min(canvas.clientWidth || 280, 320));
        const dpr = Math.min(window.devicePixelRatio || 1, 2);
        canvas.width = Math.round(px * dpr);
        canvas.height = Math.round(px * dpr);
        canvas.style.width = px + 'px';
        canvas.style.height = px + 'px';
        const ctx = canvas.getContext('2d');
        const scale = px / size;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.fillStyle = options.light || '#0C0B12';
        ctx.fillRect(0, 0, px, px);
        ctx.fillStyle = options.dark || '#E8FAFF';
        for (let y = 0; y < qr.size; y++) {
            for (let x = 0; x < qr.size; x++) {
                if (qr.getModule(x, y)) {
                    const rx = (x + border) * scale;
                    const ry = (y + border) * scale;
                    ctx.fillRect(rx, ry, scale + 0.25, scale + 0.25);
                }
            }
        }
    }

    function decodeImageData(imageData) {
        if (!global.jsQR || !imageData) {
            return null;
        }
        const r = jsQR(imageData.data, imageData.width, imageData.height, { inversionAttempts: 'dontInvert' });
        return r && r.data ? parsePayload(r.data) : null;
    }

    global.TrevixVincriptar = {
        ALPHABET,
        normalize,
        payloadFor,
        formatDisplay,
        parsePayload,
        renderCanvas,
        decodeImageData,
    };
})(window);