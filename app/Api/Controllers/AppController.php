<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Reply;
use Trevix\Core\Config;
use Trevix\Models\AppSetting;
use Trevix\Models\Community;
use Trevix\Models\Post;
use Trevix\Models\Report;
use Trevix\Models\Song;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Services\AccountService;
use Trevix\Services\Giphy;
use Trevix\Services\MusicCatalog;
use Trevix\Services\ProfileService;
use Trevix\Services\StoryOverlays;

/** GET /app/config: datos públicos que la app necesita antes de iniciar sesión. */
final class AppController extends ApiController
{
    public function config(): never
    {
        $limits = (array) Config::get('app.limits');
        $uploads = (array) Config::get('app.uploads');
        Reply::ok([
            'name'                       => (string) Config::get('app.name'),
            'api_version'                => 1,
            'maintenance'                => AppSetting::flag('maintenance_mode'),
            'registration_open'          => AccountService::registrationOpen(),
            'require_email_verification' => AppSetting::flag('require_email_verification'),
            'announcement'               => (string) (AppSetting::all()['site_announcement'] ?? ''),
            'password_min_length'        => (int) Config::get('app.security.password_min_length'),
            'limits'                     => [
                'post_body'         => (int) $limits['post_body'],
                'comment_body'      => (int) $limits['comment_body'],
                'message_body'      => (int) $limits['message_body'],
                'bio'               => (int) $limits['bio'],
                'display_name'      => (int) $limits['display_name'],
                'story_text'        => (int) $limits['story_text'],
                'story_caption'     => (int) $limits['story_caption'],
                'community_name'    => (int) $limits['community_name'],
                'community_description' => (int) $limits['community_description'],
                'report_details'    => (int) $limits['report_details'],
                'max_files_per_post' => (int) $uploads['max_files_per_post'],
                'image_max_bytes'   => (int) $uploads['image']['max_bytes'],
                'video_max_bytes'   => (int) $uploads['video']['max_bytes'],
                'video_max_seconds' => (int) $uploads['video']['max_seconds'],
                'profile_image_max_bytes' => (int) $uploads['profile']['max_bytes'],
                'story_video_max_bytes'   => (int) $uploads['story_video_max_bytes'],
                'story_video_seconds'     => (int) $uploads['story_video_seconds'],
                'song_title'        => (int) $limits['song_title'],
                'song_featuring'    => (int) $limits['song_featuring'],
                'song_clip_seconds' => (int) $limits['song_clip_seconds'],
                'story_song_seconds' => (int) $limits['story_song_seconds'],
                'audio_max_bytes'   => (int) $uploads['audio']['max_bytes'],
                'audio_min_seconds' => (int) $uploads['audio']['min_seconds'],
                'audio_max_seconds' => (int) $uploads['audio']['max_seconds'],
                'voice_max_bytes'   => (int) $uploads['voice']['max_bytes'],
                'voice_min_seconds' => (int) $uploads['voice']['min_seconds'],
                'voice_max_seconds' => (int) $uploads['voice']['max_seconds'],
            ],
            'features'           => [
                'gifs'          => Giphy::enabled(),
                'music_catalogs' => MusicCatalog::SOURCES,
                'voice_notes'   => true,
            ],
            'audio_extensions'   => array_values((array) $uploads['audio']['extensions']),
            'audio_mimes'        => array_values((array) $uploads['audio']['mimes']),
            'account_types'      => User::ACCOUNT_TYPES,
            'creator_categories' => User::CREATOR_CATEGORIES,
            'song_genres'        => Song::GENRES,
            'song_statuses'      => Song::STATUSES,
            'image_mimes'        => array_values((array) $uploads['image']['mimes']),
            'video_mimes'        => array_values((array) $uploads['video']['mimes']),
            'post_formats'       => Post::FORMATS,
            'post_visibilities'  => Post::VISIBILITIES,
            'story_backgrounds'  => Story::BACKGROUNDS,
            'life_events'        => array_map(static fn (array $e): string => $e[0], Post::LIFE_EVENTS),
            'story_filters'      => StoryOverlays::FILTERS,
            'story_text_colors'  => StoryOverlays::TEXT_COLORS,
            'message_privacy'    => User::MESSAGE_PRIVACY,
            'community_categories'   => Community::CATEGORIES,
            'community_visibilities' => Community::VISIBILITIES,
            'report_types'       => Report::TYPES,
            'report_reasons'     => Report::REASONS,
            'countries'          => ProfileService::countries(),
        ]);
    }
}
