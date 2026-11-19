# Sube el backend de Alpha 2.3 (46) a treviix.app vía TUS y documenta la migración MySQL.
# Requiere credenciales TUS (misma rutina que deploys anteriores en el proyecto).
param(
    [string]$Domain = 'trevix.ond-s.com',
    [string]$Username = 'u762375443'
)

$root = Split-Path $PSScriptRoot -Parent
$files = @(
    'app/Services/PayPalCheckout.php',
    'app/Services/MediaUpload.php',
    'app/Services/CommentService.php',
    'app/Services/WalletService.php',
    'app/Services/StoryOverlays.php',
    'app/Models/Comment.php',
    'app/Models/Wallet.php',
    'app/Api/Present.php',
    'app/Api/Controllers/PostController.php',
    'app/Api/Controllers/WalletController.php',
    'app/Api/routes.php',
    'app/Controllers/CommentController.php',
    'app/Controllers/Admin/WalletController.php',
    'app/Views/admin/wallet.php',
    'app/Views/partials/comment.php',
    'config/app.php',
    'config/local.example.php',
    'database/migrations/040_comment_media_paypal.sql'
)

Write-Host "Archivos a subir a $Domain ($($files.Count)):" 
$files | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "1. Ejecuta en MySQL (producción):" 
Write-Host "   database/migrations/040_comment_media_paypal.sql"
Write-Host "2. Añade PayPal en config/local.php (servidor): paypal.client_id, paypal.secret, paypal.mode"
Write-Host "3. Admin > Monedero: medio de pago tipo PayPal si quieres checkout automático"
Write-Host "4. Sube con scripts/upload-alpha46.ps1 (TUS: {HX_BASE}/{ruta}?override=true, sin /tus/ extra)"