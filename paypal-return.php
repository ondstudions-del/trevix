<?php
declare(strict_types=1);

/**
 * PayPal redirige aquí tras aprobar o cancelar.
 * Intenta volver a la app (deep link) y muestra instrucciones claras.
 */
$cancel = isset($_GET['cancel']);
$token = (string) ($_GET['token'] ?? '');
$deep = 'trevix://open/wallet.php?paypal=' . ($cancel ? 'cancel' : 'ok')
    . ($token !== '' ? '&order=' . rawurlencode($token) : '');
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>TREVIX · PayPal</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #0b1220; color: #e7edf7; margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; text-align: center; }
        p { max-width: 22rem; line-height: 1.5; }
        a.btn { display: inline-block; margin-top: 16px; padding: 12px 18px; border-radius: 999px; background: linear-gradient(135deg,#7c3aed,#a855f7); color: #fff; text-decoration: none; font-weight: 700; }
        .muted { color: #94a3b8; font-size: 0.9rem; margin-top: 12px; }
    </style>
</head>
<body>
    <?php if ($cancel): ?>
        <div>
            <p>Pago cancelado. Vuelve a TREVIX para intentar de nuevo.</p>
            <a class="btn" href="<?= htmlspecialchars($deep, ENT_QUOTES, 'UTF-8') ?>">Abrir TREVIX</a>
        </div>
    <?php else: ?>
        <div>
            <p>Pago listo. Vuelve a TREVIX y pulsa <strong>Confirmar pago</strong> para acreditar el saldo.</p>
            <a class="btn" href="<?= htmlspecialchars($deep, ENT_QUOTES, 'UTF-8') ?>">Abrir TREVIX y confirmar</a>
            <p class="muted">Si no se abre sola, cierra esta pestaña y pulsa Confirmar pago en la app.</p>
        </div>
    <?php endif; ?>
    <script>
        setTimeout(function () {
            try { window.location.href = <?= json_encode($deep, JSON_UNESCAPED_SLASHES) ?>; } catch (e) {}
        }, 300);
        setTimeout(function () { try { window.close(); } catch (e) {} }, 1200);
    </script>
</body>
</html>
