<?php
declare(strict_types=1);

/**
 * PayPal redirige aquí tras aprobar o cancelar. Cierra el navegador y vuelve a la app (recarga → Confirmar pago).
 */
$cancel = isset($_GET['cancel']);
$token = (string) ($_GET['token'] ?? '');
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
        a { color: #7dd3fc; }
    </style>
</head>
<body>
    <?php if ($cancel): ?>
        <p>Pago cancelado. Puedes cerrar esta ventana y volver a TREVIX.</p>
    <?php else: ?>
        <p>Pago recibido. Cierra esta pestaña, vuelve a TREVIX y pulsa <strong>Confirmar pago</strong> para acreditar el saldo.</p>
    <?php endif; ?>
    <script>
        setTimeout(function () { try { window.close(); } catch (e) {} }, 400);
    </script>
</body>
</html>