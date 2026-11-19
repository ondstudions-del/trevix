<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\Auth;
use Trevix\Models\Ad;
use Trevix\Models\AndroidEarlyAccess;
use Trevix\Models\Appeal;
use Trevix\Models\Report;
use Trevix\Models\Song;
use Trevix\Models\Support;
use Trevix\Models\VerificationRequest;
use Trevix\Models\Wallet;

/** Contadores del menú de administración (mismas claves que el panel web). */
final class AdminBadges
{
    /**
     * @return array{
     *   reports:int,music:int,support:int,appeals:int,verification:int,wallet:int,ads:int,early_access:int
     * }
     */
    public static function forStaff(array $staff): array
    {
        $isAdmin = Auth::hasRole('admin', $staff);
        $badges = [
            'reports'      => Report::openCount(),
            'music'        => Song::pendingCount(),
            'support'      => Support::openCount(),
            'appeals'      => Appeal::pendingCount(),
            'verification' => VerificationRequest::pendingCount(),
            'wallet'       => Wallet::pendingCount(),
            'ads'          => Ad::reviewCount(),
            'early_access' => 0,
        ];
        try {
            $badges['early_access'] = AndroidEarlyAccess::pendingCount();
        } catch (\Throwable) {
            // Tabla aún no migrada.
        }
        if (!$isAdmin) {
            $badges['verification'] = 0;
            $badges['wallet'] = 0;
            $badges['ads'] = 0;
            $badges['early_access'] = 0;
        }

        return $badges;
    }
}