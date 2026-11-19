/*
 * TREVIX · VINCODE / VINCRIPTAR
 * Capa de datos: anillo de módulos cian/violeta (estable).
 * Capa decorativa: # + partículas (prototipo; animación no altera el anillo).
 */
(function (global) {
    'use strict';

    const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    const SYNC = [1, 0, 1, 0, 1, 0, 1, 0];
    const DATA_BITS = 48; // 8 chars × 5 + CRC8
    const MODULES = SYNC.length + DATA_BITS; // 56

    function normalizeCode(raw) {
        let s = String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
        s = s.replace(/O/g, '0').replace(/[IL]/g, '1').replace(/U/g, 'V');
        return s;
    }

    function seedFor(code) {
        let h = 0;
        const c = normalizeCode(code);
        for (let i = 0; i < c.length; i++) {
            h = ((h << 5) - h + c.charCodeAt(i)) | 0;
        }
        return h >>> 0;
    }

    function crc8(bytes) {
        let crc = 0;
        for (let i = 0; i < bytes.length; i++) {
            crc ^= bytes[i];
            for (let b = 0; b < 8; b++) {
                crc = (crc & 0x80) ? ((crc << 1) ^ 0x07) & 0xff : (crc << 1) & 0xff;
            }
        }
        return crc;
    }

    function codeToBits(code) {
        const c = normalizeCode(code);
        if (c.length !== 8) {
            return null;
        }
        const vals = [];
        for (let i = 0; i < 8; i++) {
            const idx = ALPHABET.indexOf(c[i]);
            if (idx < 0) {
                return null;
            }
            vals.push(idx);
        }
        const bits = [];
        for (let i = 0; i < 8; i++) {
            for (let b = 4; b >= 0; b--) {
                bits.push((vals[i] >> b) & 1);
            }
        }
        const crc = crc8(vals);
        for (let b = 7; b >= 0; b--) {
            bits.push((crc >> b) & 1);
        }
        return SYNC.concat(bits);
    }

    function bitsToCode(bits) {
        if (!bits || bits.length < MODULES) {
            return null;
        }
        // Buscar sync en rotaciones del anillo.
        for (let rot = 0; rot < MODULES; rot++) {
            const rotated = bits.slice(rot).concat(bits.slice(0, rot));
            let syncOk = true;
            for (let i = 0; i < SYNC.length; i++) {
                if (rotated[i] !== SYNC[i]) {
                    syncOk = false;
                    break;
                }
            }
            if (!syncOk) {
                continue;
            }
            const data = rotated.slice(SYNC.length, SYNC.length + DATA_BITS);
            const vals = [];
            for (let i = 0; i < 8; i++) {
                let v = 0;
                for (let b = 0; b < 5; b++) {
                    v = (v << 1) | data[i * 5 + b];
                }
                if (v >= ALPHABET.length) {
                    vals.length = 0;
                    break;
                }
                vals.push(v);
            }
            if (vals.length !== 8) {
                continue;
            }
            let crc = 0;
            for (let b = 0; b < 8; b++) {
                crc = (crc << 1) | data[40 + b];
            }
            if (crc !== crc8(vals)) {
                continue;
            }
            return vals.map((v) => ALPHABET[v]).join('');
        }
        return null;
    }

    function randomFactory(n) {
        return function () {
            n = (Math.imul(n, 1664525) + 1013904223) >>> 0;
            return n / 4294967296;
        };
    }

    function buildDecor(seed) {
        const random = randomFactory(seed || 1);
        const particles = [];
        const ringDots = [];
        function addStroke(x1, y1, x2, y2, count, spread, kind) {
            for (let i = 0; i < count; i++) {
                const t = count === 1 ? 0.5 : i / (count - 1);
                const jitter = (random() - 0.5) * spread;
                particles.push({
                    x: x1 + (x2 - x1) * t + (Math.abs(y2 - y1) > Math.abs(x2 - x1) ? jitter : 0),
                    y: y1 + (y2 - y1) * t + (Math.abs(x2 - x1) >= Math.abs(y2 - y1) ? jitter : 0),
                    phase: random() * Math.PI * 2,
                    speed: 2.2 + random() * 3.8,
                    drift: 0.012 + random() * 0.026,
                    radius: 0.0018 + random() * 0.0015,
                    hue: 180 + random() * 115,
                    kind,
                });
            }
        }
        addStroke(-0.31, -0.37, -0.17, 0.37, 33, 0.075, 'hash');
        addStroke(0.17, -0.37, 0.31, 0.37, 33, 0.075, 'hash');
        addStroke(-0.39, -0.13, 0.39, -0.13, 39, 0.075, 'hash');
        addStroke(-0.39, 0.13, 0.39, 0.13, 39, 0.075, 'hash');
        for (let i = 0; i < 132; i++) {
            const a = (i / 132) * Math.PI * 2;
            ringDots.push({
                a,
                phase: random() * Math.PI * 2,
                radius: 0.004 + random() * 0.002,
                hue: 185 + random() * 115,
                speed: 1.2 + random() * 2.2,
            });
        }
        for (let i = 0; i < 48; i++) {
            const a = random() * Math.PI * 2;
            const r = 0.12 + random() * 0.3;
            particles.push({
                x: Math.cos(a) * r,
                y: Math.sin(a) * r,
                phase: random() * Math.PI * 2,
                speed: 2 + random() * 4,
                drift: 0.025 + random() * 0.045,
                radius: 0.0012 + random() * 0.0015,
                hue: 185 + random() * 120,
                kind: 'ambient',
            });
        }
        return { particles, ringDots };
    }

    /** Dibuja VINCODE en canvas. modules[] no se animan. */
    function mount(canvas, opts) {
        const code = normalizeCode(opts.code || '');
        const modules = codeToBits(code);
        if (!modules) {
            return { destroy() {} };
        }
        const seed = opts.seed != null ? (opts.seed >>> 0) : seedFor(code);
        const decor = buildDecor(seed);
        const reduce = document.documentElement.classList.contains('reduce-motion')
            || window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        const ctx = canvas.getContext('2d');
        let size = 0;
        let dpr = 1;
        let raf = 0;
        let alive = true;

        function resize() {
            dpr = Math.min(window.devicePixelRatio || 1, 2);
            const parent = canvas.parentElement;
            const box = parent ? Math.min(parent.clientWidth || 320, 420) : 320;
            size = Math.max(240, box);
            canvas.width = Math.round(size * dpr);
            canvas.height = Math.round(size * dpr);
            canvas.style.width = size + 'px';
            canvas.style.height = size + 'px';
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        function draw(ms) {
            if (!alive) {
                return;
            }
            const t = (ms || 0) * 0.001;
            const s = size;
            const cx = s / 2;
            const cy = s / 2;
            const R = s * 0.435;
            const dataR = s * 0.455;
            ctx.clearRect(0, 0, s, s);

            const plate = ctx.createRadialGradient(cx, cy, s * 0.06, cx, cy, R * 0.9);
            plate.addColorStop(0, 'rgba(12,11,18,.95)');
            plate.addColorStop(0.82, 'rgba(10,9,16,.9)');
            plate.addColorStop(1, 'rgba(0,0,0,0)');
            ctx.fillStyle = plate;
            ctx.beginPath();
            ctx.arc(cx, cy, R * 0.9, 0, Math.PI * 2);
            ctx.fill();

            const breath = reduce ? 1 : 0.94 + 0.06 * Math.sin(t * 2.2);
            ctx.beginPath();
            ctx.arc(cx, cy, dataR + s * 0.02, 0, Math.PI * 2);
            ctx.strokeStyle = 'rgba(105,220,255,.16)';
            ctx.lineWidth = Math.max(1.5, s * 0.004);
            ctx.stroke();

            for (let i = 0; i < MODULES; i++) {
                const a0 = (i / MODULES) * Math.PI * 2 - Math.PI / 2;
                const a1 = ((i + 0.9) / MODULES) * Math.PI * 2 - Math.PI / 2;
                ctx.beginPath();
                ctx.arc(cx, cy, dataR, a0, a1);
                ctx.lineWidth = Math.max(5, s * 0.028) * breath;
                ctx.lineCap = 'round';
                ctx.strokeStyle = modules[i] ? 'rgba(60,235,255,.96)' : 'rgba(139,92,246,.94)';
                ctx.stroke();
            }

            const core = s * 0.14;
            ctx.beginPath();
            ctx.arc(cx, cy, core, 0, Math.PI * 2);
            ctx.fillStyle = '#15141D';
            ctx.fill();
            ctx.strokeStyle = 'rgba(55,230,255,.33)';
            ctx.lineWidth = Math.max(1.5, s * 0.004);
            ctx.stroke();

            const lr = s * 0.055;
            ctx.strokeStyle = '#37E6FF';
            ctx.lineWidth = Math.max(2.5, s * 0.012);
            ctx.lineCap = 'round';
            ctx.beginPath();
            ctx.arc(cx - lr * 0.35, cy, lr, -Math.PI * 0.85, Math.PI * 0.3);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(cx + lr * 0.35, cy, lr, Math.PI * 0.15, Math.PI * 1.3);
            ctx.stroke();

            if (!reduce) {
                const pulse = 0.08 + 0.04 * Math.sin(t * 3);
                ctx.beginPath();
                ctx.arc(cx, cy, dataR * (1 + pulse), 0, Math.PI * 2);
                ctx.strokeStyle = 'rgba(55,230,255,.22)';
                ctx.lineWidth = Math.max(1, s * 0.003);
                ctx.stroke();
            }

            raf = requestAnimationFrame(draw);
        }

        resize();
        window.addEventListener('resize', resize);
        raf = requestAnimationFrame(draw);

        return {
            destroy() {
                alive = false;
                cancelAnimationFrame(raf);
                window.removeEventListener('resize', resize);
            },
        };
    }

    /**
     * Decodifica VINCODE desde ImageData (frame de cámara / canvas).
     * Muestrea el anillo exterior midiendo luminancia cian vs violeta.
     */
    const DATA_R_FACTORS = [0.455, 0.448, 0.462, 0.435];

    function sampleBitsFromImageData(imageData, radiusFactor) {
        const { width, height, data } = imageData;
        const cx = width / 2;
        const cy = height / 2;
        const R = Math.min(width, height) * radiusFactor;
        const bits = [];
        for (let i = 0; i < MODULES; i++) {
            const a = (i / MODULES) * Math.PI * 2 - Math.PI / 2;
            let cyan = 0;
            let violet = 0;
            let n = 0;
            for (let dr = -3; dr <= 3; dr++) {
                for (let da = -0.012; da <= 0.012; da += 0.006) {
                    const rr = R + dr;
                    const x = Math.round(cx + Math.cos(a + da) * rr);
                    const y = Math.round(cy + Math.sin(a + da) * rr);
                    if (x < 0 || y < 0 || x >= width || y >= height) {
                        continue;
                    }
                    const o = (y * width + x) * 4;
                    const r = data[o];
                    const g = data[o + 1];
                    const b = data[o + 2];
                    cyan += g + b - r;
                    violet += r + b - g;
                    n += 1;
                }
            }
            if (n === 0) {
                bits.push(0);
            } else {
                bits.push(cyan / n > violet / n ? 1 : 0);
            }
        }
        return bits;
    }

    function decodeFromImageData(imageData) {
        for (let i = 0; i < DATA_R_FACTORS.length; i++) {
            const code = bitsToCode(sampleBitsFromImageData(imageData, DATA_R_FACTORS[i]));
            if (code) {
                return code;
            }
        }
        return null;
    }

    global.TrevixVincode = {
        ALPHABET,
        MODULES,
        normalizeCode,
        seedFor,
        codeToBits,
        bitsToCode,
        mount,
        decodeFromImageData,
        payloadFor(code) {
            return 'trevix://vincode/' + normalizeCode(code);
        },
        parsePayload(text) {
            const t = String(text || '');
            const m = t.match(/trevix:\/\/vincode\/([A-Z0-9]{6,12})/i)
                || t.match(/\b([0-9A-Z]{8})\b/i);
            return m ? normalizeCode(m[1]) : null;
        },
    };
})(window);
