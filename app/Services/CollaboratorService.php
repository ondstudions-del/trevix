<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Database;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Block;
use Trevix\Models\Collaborator;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\Warning;
use Trevix\Models\Wallet;
use Trevix\Services\VerificationService;

/**
 * Colaborador: cualquier cuenta puede solicitarlo. Si no cumple requisitos, paga una tarifa única;
 * si los cumple, la solicitud es gratis. Al aceptar: 80 % de ganancias; verificado solo si la cuenta está limpia.
 * También puede activar el plan sola si cumple seguidores + story con vistas.
 */
final class CollaboratorService
{
    /** Impulso de una publicación a más personas: cada 90 días. */
    public const BOOST_DAYS = 90;

    public static function rules(): array
    {
        $int = static function (string $key, int $min, int $max): int {
            $value = AppSetting::get($key);
            return max($min, min($max, (int) (is_numeric($value) ? $value : AppSetting::DEFAULTS[$key])));
        };
        $minPrice = WalletService::settingCents('collab_min_price');
        $applyFee = WalletService::settingCents('collab_apply_fee', 0);
        return [
            'min_followers'   => $int('collab_min_followers', 0, 100000000),
            'min_story_views' => $int('collab_min_avg_views', 0, 100000000),
            'story_days'      => $int('collab_views_days', 1, 365),
            'commission'      => $int('collab_commission', 0, 90),
            'creator_share'   => 100 - $int('collab_commission', 0, 90),
            'apply_fee'       => max(0, $applyFee),
            'min_price'       => $minPrice,
            'max_price'       => max($minPrice, WalletService::settingCents('collab_max_price')),
            'max_days'        => $int('collab_max_days', 1, 3650),
            'boost_days'      => self::BOOST_DAYS,
        ];
    }

    /** Requisitos y si la cuenta los cumple ahora mismo. */
    public static function eligibility(array $user): array
    {
        $rules = self::rules();
        $id = (int) $user['id'];
        $followers = User::followersCount($id);
        $story = Collaborator::bestStoryViews($id, $rules['story_days']);
        $n = static fn (int $v) => locale() === 'en' ? number_format($v, 0, '.', ',') : number_format($v, 0, ',', '.');
        $fee = $rules['apply_fee'];
        $followersOk = $followers >= $rules['min_followers'];
        $storyOk = $story['views'] >= $rules['min_story_views'];
        $meetsRequirements = $followersOk && $storyOk;
        $feeRequired = !$meetsRequirements;
        $feePaid = Collaborator::hasPaidApplicationFee($id);
        $feeOk = !$feeRequired || $feePaid;

        $checks = [
            [
                'key'      => 'followers',
                'label'    => t('Mínimo {n} seguidores', ['n' => $n($rules['min_followers'])]),
                'ok'       => $followersOk,
                'current'  => $followers,
                'required' => $rules['min_followers'],
                'detail'   => $followers === 1 ? t('Tienes {n} seguidor.', ['n' => $n($followers)]) : t('Tienes {n} seguidores.', ['n' => $n($followers)]),
            ],
            [
                'key'      => 'story_views',
                'label'    => t('Al menos {views} visualizaciones en una historia de la última semana', ['views' => $n($rules['min_story_views'])]),
                'ok'       => $storyOk,
                'current'  => $story['views'],
                'required' => $rules['min_story_views'],
                'detail'   => $story['views'] > 0
                    ? t('Tu mejor historia de los últimos {days} días tiene {views} visualizaciones.', ['days' => $rules['story_days'], 'views' => $n($story['views'])])
                    : t('No tienes historias con visualizaciones en los últimos {days} días.', ['days' => $rules['story_days']]),
            ],
            [
                'key'      => 'fee',
                'label'    => t('Pago único de {amount} (solo si no cumples los requisitos)', ['amount' => WalletService::money($fee)]),
                'ok'       => $feeOk,
                'current'  => $feePaid || !$feeRequired ? 1 : 0,
                'required' => $feeRequired ? 1 : 0,
                'optional' => !$feeRequired,
                'detail'   => !$feeRequired
                    ? t('Cumples los requisitos: no hace falta pagar la tarifa.')
                    : ($feePaid
                        ? t('Ya pagaste la tarifa de solicitud.')
                        : t('Si no cumples seguidores o vistas, se cobra {amount} al enviar la solicitud.', ['amount' => WalletService::money($fee)])),
            ],
        ];
        $granted = Collaborator::isGranted($id);
        $application = Collaborator::latestApplication($id);
        return [
            'eligible'            => $granted || $meetsRequirements,
            'meets_requirements'  => $meetsRequirements,
            'fee_required'        => $feeRequired,
            'granted'             => $granted,
            'checks'              => $checks,
            'application'         => $application,
            'benefits'            => [
                t('Te quedas con el {pct} % de lo que pagan por tu plan.', ['pct' => $rules['creator_share']]),
                t('Puedes obtener el verificado si tu cuenta no tiene advertencias, restricciones ni otros problemas.'),
                t('Puedes impulsar 1 publicación a más personas cada {days} días.', ['days' => $rules['boost_days']]),
            ],
        ];
    }

    /** Cuenta limpia para otorgar verificado con el plan de colaborador. */
    public static function accountCleanForVerified(array $user): bool
    {
        if (($user['status'] ?? '') !== 'active') {
            return false;
        }
        if (Guard::restrictionInfo($user) !== null) {
            return false;
        }
        $days = VerificationService::rules()['warning_days'];
        return Warning::latestActiveSince((int) $user['id'], $days) === null;
    }

    /** Intenta dar verificado solo si la cuenta está limpia. Devuelve true si se otorgó. */
    private static function maybeGrantVerified(array $actor, array $target): bool
    {
        if (!empty($target['is_verified']) || !self::accountCleanForVerified($target)) {
            return false;
        }
        try {
            Moderation::setVerified($actor, $target, true);
            return true;
        } catch (\Throwable) {
            return false;
        }
    }

    /** Habilita la cuenta como colaboradora sin exigirle los requisitos (solo administración). */
    public static function grant(array $actor, string $username, string $note): array
    {
        WalletService::assertAdmin($actor);
        $user = self::grantTarget($username);
        $note = Guard::singleLine($note, 255);
        if (!Collaborator::grant((int) $user['id'], (int) $actor['id'], $note)) {
            throw new ActionError('Esa cuenta ya estaba habilitada como colaboradora.', 409);
        }
        AuditLog::record((int) $actor['id'], 'wallet.collaborator_grant', 'user', (int) $user['id'], array_filter(['username' => $user['username'], 'note' => $note]));
        Notification::notifySystem((int) $user['id'], 'collaborator_enabled', (int) $user['id']);
        return $user;
    }

    /** Quita la habilitación. Si ya activó su plan lo conserva (los requisitos solo se piden la primera vez). */
    public static function revokeGrant(array $actor, int $userId): void
    {
        WalletService::assertAdmin($actor);
        if (!Collaborator::revokeGrant($userId)) {
            throw new ActionError('Esa cuenta no estaba habilitada.', 404);
        }
        $username = User::findActiveById($userId)['username'] ?? null;
        AuditLog::record((int) $actor['id'], 'wallet.collaborator_revoke', 'user', $userId, array_filter(['username' => $username]));
    }

    private static function grantTarget(string $username): array
    {
        $user = User::findByUsername(ltrim(trim($username), '@'));
        if ($user === null || ($user['status'] ?? '') !== 'active') {
            throw ActionError::fields(['username' => t('No hay ninguna cuenta activa con ese usuario.')]);
        }
        return $user;
    }

    /** Estado completo para Ajustes › Colaborador. */
    public static function status(array $user): array
    {
        $id = (int) $user['id'];
        $plan = Collaborator::plan($id);
        $rules = self::rules();
        $eligibility = self::eligibility($user);
        $earnings = Collaborator::earnings($id);
        $boostAt = Collaborator::boostAt($id);
        $canBoost = $boostAt === null || strtotime($boostAt) <= time() - ($rules['boost_days'] * 86400);
        $nextBoost = $boostAt !== null && !$canBoost
            ? date('c', strtotime($boostAt) + ($rules['boost_days'] * 86400))
            : null;
        return [
            'active'          => $plan !== null && (bool) $plan['is_active'],
            'plan'            => $plan !== null ? self::presentPlan($plan) : null,
            'eligible'            => $eligibility['eligible'],
            'meets_requirements'  => $eligibility['meets_requirements'],
            'fee_required'        => $eligibility['fee_required'],
            'granted'             => $eligibility['granted'],
            'can_activate'        => $plan !== null || $eligibility['eligible'] || $eligibility['granted'],
            'can_apply'           => !$eligibility['granted'] && $plan === null
                && ($eligibility['application'] === null || ($eligibility['application']['status'] ?? '') === 'rejected'),
            'checks'              => $eligibility['checks'],
            'benefits'            => $eligibility['benefits'],
            'application'         => $eligibility['application'],
            'account_clean'       => self::accountCleanForVerified($user),
            'rules'               => [
                'commission'    => $rules['commission'],
                'creator_share' => $rules['creator_share'],
                'apply_fee'     => WalletService::amount($rules['apply_fee']),
                'min_price'     => WalletService::amount($rules['min_price']),
                'max_price'     => WalletService::amount($rules['max_price']),
                'max_days'      => $rules['max_days'],
                'boost_days'    => $rules['boost_days'],
            ],
            'boost'           => [
                'can_boost'   => $eligibility['granted'] || $plan !== null ? $canBoost : false,
                'last_at'     => $boostAt,
                'next_at'     => $nextBoost,
            ],
            'stats'           => [
                'subscribers'     => Collaborator::activeSubscribers($id),
                'sales'           => $earnings['sales'],
                'earned'          => WalletService::amount($earnings['earned']),
                'exclusive_posts' => Collaborator::exclusivePosts($id),
            ],
        ];
    }

    /**
     * Cualquier usuario puede solicitar ser colaborador.
     * El pago único solo se cobra si no cumple seguidores + vistas de story; si los cumple, la solicitud es gratis.
     * Si el equipo la acepta, queda habilitada sin exigir los requisitos.
     */
    public static function apply(array $user, ?string $note = null): array
    {
        $id = (int) $user['id'];
        Guard::verifiedEmail($user);
        if (Collaborator::isGranted($id) || Collaborator::plan($id) !== null) {
            throw new ActionError('Ya eres colaborador o ya tienes un plan activo.', 409);
        }
        $pending = Collaborator::latestApplication($id);
        if ($pending !== null && ($pending['status'] ?? '') === 'pending') {
            throw new ActionError('Ya tienes una solicitud en revisión.', 409);
        }
        $eligibility = self::eligibility($user);
        $feeRequired = !empty($eligibility['fee_required']);
        $fee = $feeRequired ? self::rules()['apply_fee'] : 0;
        $note = Guard::singleLine((string) $note, 500);
        Database::transaction(static function () use ($id, $fee, $note): void {
            Wallet::lock($id);
            if ($fee > 0) {
                $balance = Wallet::apply($id, -$fee, 'adjustment', [], t('Tarifa de solicitud de colaborador'));
                if ($balance === null) {
                    throw new ActionError(t('Tu saldo no alcanza: la solicitud cuesta {amount}. Recarga tu monedero.', [
                        'amount' => WalletService::money($fee),
                    ]), 402);
                }
            }
            Collaborator::createApplication($id, $fee, $fee > 0, $note);
        });
        return self::status($user);
    }

    /** Aprueba una solicitud: habilita sin requisitos; da verificado solo si la cuenta está limpia. */
    public static function approveApplication(array $actor, int $applicationId, ?string $note = null): void
    {
        WalletService::assertAdmin($actor);
        $app = Collaborator::application($applicationId);
        if ($app === null || ($app['status'] ?? '') !== 'pending') {
            throw new ActionError('Esa solicitud ya no está pendiente.', 404);
        }
        $userId = (int) $app['user_id'];
        $note = Guard::singleLine((string) $note, 500);
        Collaborator::reviewApplication($applicationId, 'approved', (int) $actor['id'], $note);
        Collaborator::grant($userId, (int) $actor['id'], $note ?: t('Solicitud de colaborador aceptada'));
        $target = User::findActiveById($userId) ?? User::findForAdmin($userId);
        $verified = false;
        if ($target !== null) {
            $verified = self::maybeGrantVerified($actor, $target);
        }
        AuditLog::record((int) $actor['id'], 'wallet.collaborator_approve', 'user', $userId, [
            'application_id' => $applicationId,
            'verified'       => $verified,
        ]);
        Notification::notifySystem($userId, 'collaborator_enabled', $userId);
    }

    public static function rejectApplication(array $actor, int $applicationId, ?string $note = null): void
    {
        WalletService::assertAdmin($actor);
        $app = Collaborator::application($applicationId);
        if ($app === null || ($app['status'] ?? '') !== 'pending') {
            throw new ActionError('Esa solicitud ya no está pendiente.', 404);
        }
        Collaborator::reviewApplication($applicationId, 'rejected', (int) $actor['id'], Guard::singleLine((string) $note, 500));
        AuditLog::record((int) $actor['id'], 'wallet.collaborator_reject', 'user', (int) $app['user_id'], ['application_id' => $applicationId]);
    }

    /** Impulsa una publicación propia (destacado) si el colaborador tiene derecho y no usó el cupo de 90 días. */
    public static function boostPost(array $user, int $postId): array
    {
        $id = (int) $user['id'];
        if (!Collaborator::isGranted($id) && Collaborator::plan($id) === null) {
            throw new ActionError('Solo los colaboradores pueden impulsar publicaciones.', 403);
        }
        $status = self::status($user);
        if (empty($status['boost']['can_boost'])) {
            throw new ActionError(t('Podrás impulsar otra publicación a partir del {date}.', [
                'date' => $status['boost']['next_at'] ? full_date((string) date('Y-m-d H:i:s', strtotime((string) $status['boost']['next_at'])), false) : '—',
            ]), 429);
        }
        $post = Post::findRaw($postId);
        if ($post === null || (int) $post['user_id'] !== $id || ($post['status'] ?? '') !== 'published') {
            throw new ActionError('Esa publicación no está disponible.', 404);
        }
        if (!Post::setFeatured($postId, $id)) {
            throw new ActionError('Esa publicación ya estaba impulsada.', 409);
        }
        Collaborator::markBoost($id);
        return ['message' => t('Impulsamos tu publicación: llegará a más personas.'), 'post_id' => $postId] + self::status($user);
    }

    /** Activa o edita el plan. $input: price (texto en USD), days, description. */
    public static function savePlan(array $user, array $input): array
    {
        $id = (int) $user['id'];
        Guard::verifiedEmail($user);
        Guard::rateLimit('collab_plan', (string) $id, 'Cambiaste tu plan muchas veces seguidas. Inténtalo en {min} min.');
        $rules = self::rules();
        $existing = Collaborator::plan($id);
        if ($existing === null && !self::eligibility($user)['eligible']) {
            throw new ActionError('Aún no cumples los requisitos para ser colaborador.', 422);
        }

        $price = WalletService::parseAmount((string) ($input['price'] ?? ''));
        $days = (int) ($input['days'] ?? 0);
        $description = Guard::singleLine((string) ($input['description'] ?? ''), 300);
        $errors = [];
        if ($price === null || $price < $rules['min_price'] || $price > $rules['max_price']) {
            $errors['price'] = t('El precio debe estar entre {min} y {max}.', [
                'min' => WalletService::money($rules['min_price']), 'max' => WalletService::money($rules['max_price']),
            ]);
        }
        if ($days < 1 || $days > $rules['max_days']) {
            $errors['days'] = t('Elige de 1 a {max} días.', ['max' => $rules['max_days']]);
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        RateLimit::hit('collab_plan', (string) $id);
        $firstTime = $existing === null;
        Collaborator::savePlan($id, (int) $price, $days, $description, true);
        if ($firstTime && self::accountCleanForVerified($user) && empty($user['is_verified'])) {
            // Sin actor staff: marca verificado directo si la cuenta está limpia.
            try {
                User::setVerified($id, true);
            } catch (\Throwable) {
                // Si el modelo no expone setVerified, no bloquea la activación del plan.
            }
        }
        return self::status($user);
    }

    /** Pausa (no acepta suscripciones nuevas; quien ya pagó conserva su acceso) o reanuda el plan. */
    public static function setActive(array $user, bool $active): array
    {
        if (!Collaborator::setActive((int) $user['id'], $active) && Collaborator::plan((int) $user['id']) === null) {
            throw new ActionError('Todavía no activaste tu plan de colaborador.', 404);
        }
        return self::status($user);
    }

    public static function canPublishExclusive(int $userId): bool
    {
        $plan = Collaborator::plan($userId);
        return $plan !== null && (bool) $plan['is_active'];
    }

    public static function assertCanPublishExclusive(int $userId): void
    {
        if (!self::canPublishExclusive($userId)) {
            throw ActionError::field('visibility', 'Activa tu plan de colaborador para publicar solo para suscriptores.');
        }
    }

    /** Visibilidades que puede elegir la persona al publicar o editar ($current: la que ya tiene la publicación). */
    public static function visibilitiesFor(int $userId, ?string $current = null): array
    {
        $all = Post::VISIBILITIES;
        if ($current !== 'subscribers' && !self::canPublishExclusive($userId)) {
            unset($all['subscribers']);
        }
        return $all;
    }

    /**
     * Lo que ve otra persona en el perfil del colaborador: el plan (si acepta suscripciones) y hasta cuándo tiene
     * acceso. null si la cuenta no es colaboradora y la persona no tiene acceso vigente.
     */
    public static function profileOffer(int $collaboratorId, int $viewerId): ?array
    {
        $plan = Collaborator::plan($collaboratorId);
        $until = $viewerId !== $collaboratorId ? Collaborator::accessUntil($viewerId, $collaboratorId) : null;
        if (($plan === null || !(bool) $plan['is_active']) && $until === null) {
            return null;
        }
        return [
            'accepting'       => $plan !== null && (bool) $plan['is_active'],
            'price'           => $plan !== null ? WalletService::amount((int) $plan['price_cents']) : null,
            'days'            => $plan !== null ? (int) $plan['period_days'] : null,
            'description'     => $plan['description'] ?? null,
            'exclusive_posts' => Collaborator::exclusivePosts($collaboratorId),
            'access_until'    => $until,
            'is_owner'        => $viewerId === $collaboratorId,
        ];
    }

    /**
     * Compra (o extiende) la suscripción con el saldo del monedero: descuenta el precio, acredita al colaborador lo
     * que queda tras la comisión y suma los días al final del acceso vigente.
     */
    public static function subscribe(array $subscriber, int $collaboratorId): array
    {
        $sid = (int) $subscriber['id'];
        Guard::verifiedEmail($subscriber);
        Guard::rateLimit('subscribe', (string) $sid, 'Hiciste muchas compras seguidas. Inténtalo en {min} min.');
        if ($sid === $collaboratorId) {
            throw new ActionError('No puedes suscribirte a tu propia cuenta.', 422);
        }
        $collaborator = User::findActiveById($collaboratorId);
        if ($collaborator === null || Block::exists($sid, $collaboratorId) || Block::exists($collaboratorId, $sid)) {
            throw new ActionError('Esta cuenta no está disponible.', 404);
        }
        $commissionPct = self::rules()['commission'];
        RateLimit::hit('subscribe', (string) $sid);

        $staffPurchase = Auth::hasRole('moderator', $subscriber);
        $result = Database::transaction(static function () use ($sid, $collaboratorId, $commissionPct, $staffPurchase): array {
            $plan = Collaborator::plan($collaboratorId);
            if ($plan === null || !(bool) $plan['is_active']) {
                throw new ActionError('Esta cuenta no acepta suscripciones ahora.', 422);
            }
            $price = (int) $plan['price_cents'];
            $days = (int) $plan['period_days'];
            Wallet::lock($sid, $collaboratorId);
            if (!$staffPurchase && Wallet::balance($sid) < $price) {
                throw new ActionError(t('Tu saldo no alcanza: la suscripción cuesta {price}. Recarga tu monedero.', ['price' => WalletService::money($price)]), 402);
            }
            $until = Collaborator::accessUntil($sid, $collaboratorId, true);
            $startsAt = $until ?? date('Y-m-d H:i:s');
            // Staff: acceso real, sin cobro ni ingreso al colaborador (billetera infinita / compra de prueba).
            $commission = $staffPurchase ? 0 : intdiv($price * $commissionPct + 50, 100);
            $charge = $staffPurchase ? 0 : $price;
            $subscriptionId = Collaborator::createSubscription($collaboratorId, $sid, $charge, $commission, $days, $startsAt);
            if ($staffPurchase) {
                $balance = Wallet::balance($sid);
            } else {
                $balance = Wallet::apply($sid, -$price, 'subscription', ['counterpart_id' => $collaboratorId, 'subscription_id' => $subscriptionId]);
                if ($balance === null) {
                    throw new ActionError('Tu saldo no alcanza. Recarga tu monedero.', 402);
                }
                if ($price - $commission > 0) {
                    Wallet::apply($collaboratorId, $price - $commission, 'earning', ['counterpart_id' => $sid, 'subscription_id' => $subscriptionId]);
                }
            }
            return [
                'subscription_id' => $subscriptionId,
                'balance'         => $balance,
                'price'           => $price,
                'days'            => $days,
                'staff'           => $staffPurchase,
            ];
        });
        if (empty($result['staff'])) {
            Notification::notifySubscription($collaboratorId, $sid, $result['subscription_id']);
        }
        $subscription = Collaborator::subscription($result['subscription_id']);
        return [
            'message'      => t('Listo: tienes acceso al contenido de {name} hasta el {date}.', [
                'name' => $collaborator['display_name'], 'date' => full_date((string) $subscription['expires_at'], false),
            ]),
            'access_until' => $subscription['expires_at'],
            'price'        => WalletService::amount($result['price']),
            'days'         => $result['days'],
            'balance'      => WalletService::amount($result['balance']),
            'welcome'      => true,
        ];
    }

    public static function presentPlan(array $plan): array
    {
        $rules = self::rules();
        $price = (int) $plan['price_cents'];
        $commission = intdiv($price * $rules['commission'] + 50, 100);
        return [
            'price'       => WalletService::amount($price),
            'days'        => (int) $plan['period_days'],
            'description' => $plan['description'],
            'is_active'   => (bool) $plan['is_active'],
            'you_receive' => WalletService::amount($price - $commission),
            'activated_at' => $plan['activated_at'],
        ];
    }
}
