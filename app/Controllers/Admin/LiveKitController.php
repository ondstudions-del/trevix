<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Session;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Services\LiveKitSettings;

/** LiveKit: URL, API Key/Secret y funciones habilitadas (llamadas y live). */
final class LiveKitController extends AdminController
{
    public function handle(): void
    {
        $this->guard('livekit');
        if (Request::isPost()) {
            $this->save();
        }
        $resolved = LiveKitSettings::resolve();
        $hasSecret = LiveKitSettings::configured() || AppSetting::get('livekit_api_secret') !== '';
        $this->page('livekit', 'livekit', [
            'livekit' => [
                'configured' => LiveKitSettings::configured(),
                'url'        => $resolved['url'] !== '' ? $resolved['url'] : AppSetting::get('livekit_url'),
                'api_key'    => $resolved['api_key'] !== '' ? $resolved['api_key'] : AppSetting::get('livekit_api_key'),
                'source'     => $resolved['source'],
                'has_secret' => $hasSecret,
                'audio'      => AppSetting::flag('livekit_calls_audio'),
                'video'      => AppSetting::flag('livekit_calls_video'),
                'live'       => AppSetting::flag('livekit_live_broadcast'),
            ],
        ]);
    }

    private function save(): never
    {
        $back = $this->sectionUrl('livekit');
        $staff = $this->beginAction('admin', $back);
        try {
            $result = LiveKitSettings::saveFromPanel(
                Request::text('livekit_url', false),
                Request::text('livekit_api_key', false),
                Request::text('livekit_api_secret', false),
                [
                    'audio_calls' => Request::input('livekit_calls_audio') === '1',
                    'video_calls' => Request::input('livekit_calls_video') === '1',
                    'live'        => Request::input('livekit_live_broadcast') === '1',
                ],
            );
            AuditLog::record((int) $staff['id'], 'settings.update', 'livekit', null, [
                'livekit' => ['', $result['url']],
            ]);
            Session::flash('success', 'LiveKit configurado. La app ya puede pedir tokens de sala.');
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($back);
    }
}