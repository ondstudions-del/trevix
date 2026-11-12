<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Services\AdService;
use Trevix\Services\MediaUpload;

/** OND-ADS: crear anuncios (se pagan con el monedero), mis anuncios, cancelar y toques en las tarjetas del feed. */
final class AdController extends ApiController
{
    /** GET /ads — precio por día, personas por día, saldo y lo que se puede promocionar. */
    public function summary(): never
    {
        AdService::settleDue();
        $s = AdService::summary($this->uid());
        $s['targets']['posts'] = array_map(static fn (array $p): array => [
            'id' => $p['id'], 'excerpt' => $p['excerpt'], 'thumb_url' => Present::file($p['thumb']), 'created_at' => Present::date($p['created_at']),
        ], $s['targets']['posts']);
        $s['targets']['communities'] = array_map(static fn (array $c): array => [
            'id' => $c['id'], 'name' => $c['name'], 'slug' => $c['slug'], 'avatar_url' => Present::file($c['avatar_path']), 'members_count' => $c['members_count'],
        ], $s['targets']['communities']);
        $s['targets']['groups'] = array_map(static fn (array $g): array => [
            'id' => $g['id'], 'title' => $g['title'], 'avatar_url' => Present::file($g['avatar_path']), 'members_count' => $g['members_count'],
        ], $s['targets']['groups']);
        Reply::ok($s);
    }

    /**
     * POST /ads (multipart) {kind: post|community|group|custom, target_id?, days, title?, body?, link_url?, cta?, image?}
     * Cobra precio por día × días del monedero (402 si no alcanza) y queda en revisión.
     */
    public function create(): never
    {
        $result = AdService::create($this->user(), [
            'kind'      => Input::str('kind'),
            'target_id' => Input::int('target_id'),
            'days'      => Input::int('days'),
            'title'     => Input::str('title'),
            'body'      => Input::str('body', false),
            'link_url'  => Input::str('link_url'),
            'cta'       => Input::str('cta') ?: 'learn_more',
        ], MediaUpload::collect('image'));
        $result['campaign'] = Present::ownAd($result['campaign']);
        Reply::ok($result, [], 201);
    }

    /** GET /me/ads?before= */
    public function mine(): never
    {
        $page = AdService::mine($this->uid(), max(0, (int) Request::query('before')));
        Reply::ok(array_map([Present::class, 'ownAd'], $page['items']), ['next' => $page['next']]);
    }

    /** POST /me/ads/{id}/cancel — en revisión se devuelve todo; activo, los días que faltan. */
    public function cancel(string $id): never
    {
        $result = AdService::cancel($this->user(), (int) $id);
        $result['campaign'] = Present::ownAd($result['campaign']);
        Reply::ok($result);
    }

    /** POST /ads/{id}/click — cuenta el toque y devuelve adónde lleva (post_id, community_slug, invite_code o url). */
    public function click(string $id): never
    {
        Reply::ok(AdService::click($this->uid(), (int) $id));
    }
}
