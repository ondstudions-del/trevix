<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Database;
use Trevix\Models\AppSetting;
use Trevix\Models\Block;
use Trevix\Models\Collaborator;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\VerificationRequest;
use Trevix\Models\Wallet;

/**
 * Colaborador: quien cumple los requisitos (seguidores, promedio de «Me gusta» y de visualizaciones) activa un plan
 * con el precio en USD y los días que quiere. Otras personas lo compran con su monedero y ven sus publicaciones
 * «Suscriptores» mientras dure el acceso. TREVIX se queda con la comisión configurada en el panel.
 * Los requisitos solo se exigen para activar el plan por primera vez; después se puede editar, pausar o reanudar.
 */
final class CollaboratorService
{
    /** Últimas publicaciones que cuentan para el promedio de «Me gusta». */
    private const RECENT_POSTS = 10;

    public static function rules(): array
    {
        $int = static function (string $key, int $min, int $max): int {
            $value = AppSetting::get($key);
            return max($min, min($max, (int) (is_numeric($value) ? $value : AppSetting::DEFAULTS[$key])));
        };
        $minPrice = WalletService::settingCents('collab_min_price');
        return [
            'min_followers' => $int('collab_min_followers', 0, 100000000),
            'min_avg_likes' => $int('collab_min_avg_likes', 0, 100000000),
            'min_avg_views' => $int('collab_min_avg_views', 0, 100000000),
            'min_posts'     => $int('collab_min_posts', 1, 50),
            'views_days'    => $int('collab_views_days', 1, 365),
            'commission'    => $int('collab_commission', 0, 90),
            'min_price'     => $minPrice,
            'max_price'     => max($minPrice, WalletService::settingCents('collab_max_price')),
            'max_days'      => $int('collab_max_days', 1, 3650),
        ];
    }

    /** Requisitos y si la cuenta los cumple ahora mismo. */
    public static function eligibility(array $user): array
    {
        $rules = self::rules();
        $id = (int) $user['id'];
        $followers = User::followersCount($id);
        $likes = VerificationRequest::likeStats($id, max(self::RECENT_POSTS, $rules['min_posts']));
        $views = Collaborator::viewStats($id, $rules['views_days']);
        $enoughPosts = $likes['posts'] >= $rules['min_posts'];
        $n = static fn (int $v) => locale() === 'en' ? number_format($v, 0, '.', ',') : number_format($v, 0, ',', '.');

        $checks = [
            [
                'key'      => 'followers',
                'label'    => t('Más de {n} seguidores', ['n' => $n($rules['min_followers'])]),
                'ok'       => $followers >= $rules['min_followers'],
                'current'  => $followers,
                'required' => $rules['min_followers'],
                'detail'   => $followers === 1 ? t('Tienes {n} seguidor.', ['n' => $n($followers)]) : t('Tienes {n} seguidores.', ['n' => $n($followers)]),
            ],
            [
                'key'      => 'likes',
                'label'    => t('Promedio de {likes} «Me gusta» en tus publicaciones', ['likes' => $n($rules['min_avg_likes'])]),
                'ok'       => $enoughPosts && $likes['avg_likes'] >= $rules['min_avg_likes'],
                'current'  => $likes['avg_likes'],
                'required' => $rules['min_avg_likes'],
                'detail'   => $enoughPosts
                    ? t('Promedio de {likes} en tus últimas {posts} publicaciones.', ['likes' => $n($likes['avg_likes']), 'posts' => $likes['posts']])
                    : t('Necesitas al menos {min} publicaciones propias (tienes {posts}).', ['min' => $rules['min_posts'], 'posts' => $likes['posts']]),
            ],
            [
                'key'      => 'views',
                'label'    => t('Promedio de {views} visualizaciones por publicación en los últimos {days} días', ['views' => $n($rules['min_avg_views']), 'days' => $rules['views_days']]),
                'ok'       => $views['posts'] > 0 && $views['avg_views'] >= $rules['min_avg_views'],
                'current'  => $views['avg_views'],
                'required' => $rules['min_avg_views'],
                'detail'   => $views['posts'] > 0
                    ? t('Promedio de {views} personas por publicación ({posts} publicaciones).', ['views' => $n($views['avg_views']), 'posts' => $views['posts']])
                    : t('No publicaste en los últimos {days} días.', ['days' => $rules['views_days']]),
            ],
        ];
        return ['eligible' => !in_array(false, array_column($checks, 'ok'), true), 'checks' => $checks];
    }

    /** Estado completo para Ajustes › Colaborador. */
    public static function status(array $user): array
    {
        $id = (int) $user['id'];
        $plan = Collaborator::plan($id);
        $rules = self::rules();
        $eligibility = self::eligibility($user);
        $earnings = Collaborator::earnings($id);
        return [
            'active'          => $plan !== null && (bool) $plan['is_active'],
            'plan'            => $plan !== null ? self::presentPlan($plan) : null,
            'eligible'        => $eligibility['eligible'],
            'can_activate'    => $plan !== null || $eligibility['eligible'],
            'checks'          => $eligibility['checks'],
            'rules'           => [
                'commission' => $rules['commission'],
                'min_price'  => WalletService::amount($rules['min_price']),
                'max_price'  => WalletService::amount($rules['max_price']),
                'max_days'   => $rules['max_days'],
            ],
            'stats'           => [
                'subscribers'     => Collaborator::activeSubscribers($id),
                'sales'           => $earnings['sales'],
                'earned'          => WalletService::amount($earnings['earned']),
                'exclusive_posts' => Collaborator::exclusivePosts($id),
            ],
        ];
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
        Collaborator::savePlan($id, (int) $price, $days, $description, true);
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

        $result = Database::transaction(static function () use ($sid, $collaboratorId, $commissionPct): array {
            $plan = Collaborator::plan($collaboratorId);
            if ($plan === null || !(bool) $plan['is_active']) {
                throw new ActionError('Esta cuenta no acepta suscripciones ahora.', 422);
            }
            $price = (int) $plan['price_cents'];
            $days = (int) $plan['period_days'];
            Wallet::lock($sid, $collaboratorId);
            if (Wallet::balance($sid) < $price) {
                throw new ActionError(t('Tu saldo no alcanza: la suscripción cuesta {price}. Recarga tu monedero.', ['price' => WalletService::money($price)]), 402);
            }
            $until = Collaborator::accessUntil($sid, $collaboratorId, true);
            $startsAt = $until ?? date('Y-m-d H:i:s');
            $commission = intdiv($price * $commissionPct + 50, 100);
            $subscriptionId = Collaborator::createSubscription($collaboratorId, $sid, $price, $commission, $days, $startsAt);
            $balance = Wallet::apply($sid, -$price, 'subscription', ['counterpart_id' => $collaboratorId, 'subscription_id' => $subscriptionId]);
            if ($balance === null) {
                throw new ActionError('Tu saldo no alcanza. Recarga tu monedero.', 402);
            }
            if ($price - $commission > 0) {
                Wallet::apply($collaboratorId, $price - $commission, 'earning', ['counterpart_id' => $sid, 'subscription_id' => $subscriptionId]);
            }
            return ['subscription_id' => $subscriptionId, 'balance' => $balance, 'price' => $price, 'days' => $days];
        });
        Notification::notifySubscription($collaboratorId, $sid, $result['subscription_id']);
        $subscription = Collaborator::subscription($result['subscription_id']);
        return [
            'message'      => t('Listo: tienes acceso al contenido de {name} hasta el {date}.', [
                'name' => $collaborator['display_name'], 'date' => full_date((string) $subscription['expires_at'], false),
            ]),
            'access_until' => $subscription['expires_at'],
            'price'        => WalletService::amount($result['price']),
            'days'         => $result['days'],
            'balance'      => WalletService::amount($result['balance']),
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
