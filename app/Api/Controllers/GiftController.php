<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Services\GiftService;
use Trevix\Services\RelationshipService;

/** Regalos (catálogo, comprar, «Mis regalos», enviar, recibidos y enviados) y la campana del perfil. Importes en USD. */
final class GiftController extends ApiController
{
    /** GET /gifts — saldo, comisión, catálogo por categorías y lo guardado en «Mis regalos». */
    public function index(): never
    {
        Reply::ok(GiftService::summary($this->uid()));
    }

    /** POST /gifts/{id}/buy {quantity} — compra unidades para enviarlas después. */
    public function buy(string $id): never
    {
        Reply::ok(GiftService::buy($this->user(), (int) $id, Input::int('quantity') ?: 1));
    }

    /**
     * POST /gifts/{id}/send {to?: usuario, source: buy|inventory, context: profile|message|post|story, ref_id?}
     * En publicación o historia, ref_id es su id y quien recibe es su autor.
     */
    public function send(string $id): never
    {
        $result = GiftService::send(
            $this->user(),
            Input::str('to'),
            (int) $id,
            Input::str('source') === 'inventory',
            Input::str('context') ?: 'profile',
            Input::int('ref_id')
        );
        $result['send']['user'] = $result['send']['user'] !== null ? Present::user($result['send']['user']) : null;
        Reply::ok($result);
    }

    /** GET /me/gifts/received?before= · GET /me/gifts/sent?before= */
    public function history(string $direction): never
    {
        $page = GiftService::history($this->uid(), $direction === 'sent' ? 'sent' : 'received', max(0, (int) Request::query('before')));
        $items = array_map(static function (array $s): array {
            $s['user'] = $s['user'] !== null ? Present::user($s['user']) : null;
            return $s;
        }, $page['items']);
        Reply::ok($items, ['next' => $page['next']]);
    }

    /** PUT /users/{id}/alerts · DELETE — activa o apaga la campana (avisos de publicaciones, notas e historias). */
    public function alerts(string $id): never
    {
        $result = RelationshipService::alerts($this->uid(), (int) $id, Request::method() !== 'DELETE');
        Reply::ok(['alerts' => $result['alerts'], 'message' => $result['message']]);
    }
}
