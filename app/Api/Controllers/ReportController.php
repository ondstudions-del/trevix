<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Reply;
use Trevix\Services\ReportService;

/** Reportar contenido o cuentas al equipo de moderación. */
final class ReportController extends ApiController
{
    /** POST /reports {type: post|comment|user|community|message|story, id, reason, details?} */
    public function create(): never
    {
        $result = ReportService::submit(
            $this->uid(),
            Input::str('type'),
            Input::int('id'),
            Input::str('reason'),
            Input::str('details', false)
        );
        Reply::ok(['status' => $result['status'], 'message' => $result['message']], [], 201);
    }
}
