<?php
declare(strict_types=1);

use Trevix\Api\Controllers\AdminController as Admin;
use Trevix\Api\Controllers\AppController as App;
use Trevix\Api\Controllers\AuthController as AuthApi;
use Trevix\Api\Controllers\CommunityController as Communities;
use Trevix\Api\Controllers\EventController as Events;
use Trevix\Api\Controllers\ExploreController as Explore;
use Trevix\Api\Controllers\GeoController as Geo;
use Trevix\Api\Controllers\GifController as Gifs;
use Trevix\Api\Controllers\MeController as Me;
use Trevix\Api\Controllers\MessageController as Messages;
use Trevix\Api\Controllers\ModerationController as Moderation;
use Trevix\Api\Controllers\MusicController as Music;
use Trevix\Api\Controllers\NoteController as Notes;
use Trevix\Api\Controllers\NotificationController as Notifications;
use Trevix\Api\Controllers\PostController as Posts;
use Trevix\Api\Controllers\PushController as Push;
use Trevix\Api\Controllers\ReportController as Reports;
use Trevix\Api\Controllers\StoryController as Stories;
use Trevix\Api\Controllers\UserController as Users;

/**
 * Rutas de la API v1 (referencia completa en docs/API.md).
 * [método, ruta relativa a /api/v1, [controlador, método, ...argumentos fijos], acceso: guest|user|moderator|admin]
 */
return [
    // App y sesión
    ['GET',    'app/config',                         [App::class, 'config'],                       'guest'],
    ['POST',   'auth/login',                         [AuthApi::class, 'login'],                    'guest'],
    ['POST',   'auth/register',                      [AuthApi::class, 'register'],                 'guest'],
    ['POST',   'auth/password/forgot',               [AuthApi::class, 'forgotPassword'],           'guest'],
    ['POST',   'auth/logout',                        [AuthApi::class, 'logout'],                   'user'],
    ['GET',    'auth/sessions',                      [AuthApi::class, 'sessions'],                 'user'],
    ['POST',   'auth/sessions/logout-others',        [AuthApi::class, 'logoutOthers'],             'user'],
    ['DELETE', 'auth/sessions/{id}',                 [AuthApi::class, 'revokeSession'],            'user'],

    // Mi cuenta
    ['GET',    'me',                                 [Me::class, 'show'],                          'user'],
    ['PATCH',  'me',                                 [Me::class, 'update'],                        'user'],
    ['DELETE', 'me',                                 [Me::class, 'destroy'],                       'user'],
    ['GET',    'me/counts',                          [Me::class, 'counts'],                        'user'],
    ['GET',    'me/push',                            [Push::class, 'poll'],                        'user'],
    ['POST',   'me/avatar',                          [Me::class, 'uploadImage', 'avatar'],         'user'],
    ['DELETE', 'me/avatar',                          [Me::class, 'deleteImage', 'avatar'],         'user'],
    ['POST',   'me/cover',                           [Me::class, 'uploadImage', 'cover'],          'user'],
    ['DELETE', 'me/cover',                           [Me::class, 'deleteImage', 'cover'],          'user'],
    ['GET',    'me/details',                         [Me::class, 'details'],                       'user'],
    ['PUT',    'me/details',                         [Me::class, 'saveDetails'],                   'user'],
    ['GET',    'me/verification',                    [Me::class, 'verification'],                  'user'],
    ['POST',   'me/verification',                    [Me::class, 'verification'],                  'user'],
    ['DELETE', 'me/verification',                    [Me::class, 'verification'],                  'user'],
    ['GET',    'me/warnings',                        [Me::class, 'warnings'],                      'user'],
    ['PUT',    'me/profile-song',                    [Me::class, 'profileSong'],                   'user'],
    ['DELETE', 'me/profile-song',                    [Me::class, 'profileSong'],                   'user'],
    ['PATCH',  'me/account',                         [Me::class, 'account'],                       'user'],
    ['POST',   'me/email/verification',              [Me::class, 'resendVerification'],            'user'],
    ['PUT',    'me/password',                        [Me::class, 'password'],                      'user'],
    ['PATCH',  'me/privacy',                         [Me::class, 'privacy'],                       'user'],
    ['PATCH',  'me/notification-settings',           [Me::class, 'notificationSettings'],          'user'],
    ['GET',    'me/blocked',                         [Me::class, 'blocked'],                       'user'],
    ['GET',    'me/follow-requests',                 [Me::class, 'followRequests'],                'user'],
    ['POST',   'me/follow-requests/{id}/accept',     [Me::class, 'resolveRequest', 'accept'],      'user'],
    ['POST',   'me/follow-requests/{id}/reject',     [Me::class, 'resolveRequest', 'reject'],      'user'],
    ['GET',    'me/saved',                           [Me::class, 'saved'],                         'user'],
    ['POST',   'me/deactivate',                      [Me::class, 'deactivate'],                    'user'],

    // Música: biblioteca y panel del artista
    ['GET',    'music',                              [Music::class, 'library'],                    'user'],
    ['GET',    'music/browse',                       [Music::class, 'browse'],                     'user'],
    ['GET',    'music/catalog/{type}',               [Music::class, 'catalog'],                    'user'],
    ['POST',   'music/catalog/{type}/import',        [Music::class, 'import'],                     'user'],
    ['GET',    'music/{id}',                         [Music::class, 'show'],                       'user'],
    ['GET',    'music/{id}/posts',                   [Music::class, 'posts'],                      'user'],
    ['GET',    'me/music',                           [Music::class, 'mine'],                       'user'],
    ['POST',   'me/music',                           [Music::class, 'submit'],                     'user'],
    ['POST',   'me/music/{id}/cancel',               [Music::class, 'manage', 'cancel'],           'user'],
    ['POST',   'me/music/{id}/withdraw',             [Music::class, 'manage', 'withdraw'],         'user'],
    ['POST',   'me/music/{id}/republish',            [Music::class, 'manage', 'republish'],        'user'],
    ['DELETE', 'me/music/{id}',                      [Music::class, 'manage', 'delete'],           'user'],

    // Personas
    ['GET',    'users/{username}',                   [Users::class, 'show'],                       'user'],
    ['GET',    'users/{username}/posts',             [Users::class, 'posts'],                      'user'],
    ['GET',    'users/{username}/followers',         [Users::class, 'connections', 'followers'],   'user'],
    ['GET',    'users/{username}/following',         [Users::class, 'connections', 'following'],   'user'],
    ['GET',    'users/{username}/stories',           [Users::class, 'stories'],                    'user'],
    ['GET',    'users/{username}/music',             [Music::class, 'byArtist'],                   'user'],
    ['POST',   'users/{id}/follow',                  [Users::class, 'follow'],                     'user'],
    ['DELETE', 'users/{id}/follow',                  [Users::class, 'unfollow'],                   'user'],
    ['DELETE', 'users/{id}/follower',                [Users::class, 'removeFollower'],             'user'],
    ['POST',   'users/{id}/block',                   [Users::class, 'block'],                      'user'],
    ['DELETE', 'users/{id}/block',                   [Users::class, 'block'],                      'user'],

    // Feed, publicaciones y comentarios
    ['GET',    'feed',                               [Posts::class, 'feed'],                       'user'],
    ['GET',    'reels',                              [Posts::class, 'reels'],                      'user'],
    ['POST',   'posts',                              [Posts::class, 'create'],                     'user'],
    ['GET',    'posts/featured',                     [Posts::class, 'featured'],                   'user'],
    ['GET',    'posts/{id}',                         [Posts::class, 'show'],                       'user'],
    ['PATCH',  'posts/{id}',                         [Posts::class, 'update'],                     'user'],
    ['DELETE', 'posts/{id}',                         [Posts::class, 'destroy'],                    'user'],
    ['POST',   'posts/{id}/like',                    [Posts::class, 'interact', 'like'],           'user'],
    ['DELETE', 'posts/{id}/like',                    [Posts::class, 'interact', 'like'],           'user'],
    ['POST',   'posts/{id}/save',                    [Posts::class, 'interact', 'save'],           'user'],
    ['DELETE', 'posts/{id}/save',                    [Posts::class, 'interact', 'save'],           'user'],
    ['GET',    'posts/{id}/comments',                [Posts::class, 'comments'],                   'user'],
    ['POST',   'posts/{id}/comments',                [Posts::class, 'comment'],                    'user'],
    ['DELETE', 'comments/{id}',                      [Posts::class, 'deleteComment'],              'user'],

    // Eventos (se crean con POST /posts y event[...])
    ['GET',    'events',                             [Events::class, 'index'],                     'user'],
    ['GET',    'events/{id}',                        [Events::class, 'show'],                      'user'],
    ['POST',   'events/{id}/respond',                [Events::class, 'respond'],                   'user'],

    // Lugar a partir de coordenadas (al publicar con la ubicación actual)
    ['GET',    'geo/reverse',                        [Geo::class, 'reverse'],                      'user'],

    // GIF y stickers (GIPHY) para comentarios y mensajes
    ['GET',    'gifs/{type}',                        [Gifs::class, 'search'],                      'user'],

    // Explorar
    ['GET',    'search',                             [Explore::class, 'search'],                   'user'],
    ['GET',    'explore',                            [Explore::class, 'index'],                    'user'],
    ['GET',    'hashtags/trending',                  [Explore::class, 'trending'],                 'user'],
    ['GET',    'hashtags/{tag}',                     [Explore::class, 'hashtag'],                  'user'],
    ['GET',    'suggestions/users',                  [Explore::class, 'suggestions'],              'user'],
    ['POST',   'suggestions/users/{id}/dismiss',     [Explore::class, 'dismiss'],                  'user'],

    // Notificaciones
    ['GET',    'notifications',                      [Notifications::class, 'index'],              'user'],
    ['POST',   'notifications/read-all',             [Notifications::class, 'readAll'],            'user'],
    ['POST',   'notifications/{id}/read',            [Notifications::class, 'read'],               'user'],

    // Mensajes
    ['GET',    'conversations',                      [Messages::class, 'index'],                   'user'],
    ['GET',    'conversations/{id}',                 [Messages::class, 'show'],                    'user'],
    ['PATCH',  'conversations/{id}',                 [Messages::class, 'update'],                  'user'],
    ['GET',    'conversations/{id}/messages',        [Messages::class, 'messages'],                'user'],
    ['GET',    'conversations/{id}/search',          [Messages::class, 'search'],                  'user'],
    ['POST',   'conversations/{id}/messages',        [Messages::class, 'reply'],                   'user'],
    ['POST',   'conversations/{id}/read',            [Messages::class, 'read'],                    'user'],
    ['POST',   'messages',                           [Messages::class, 'create'],                  'user'],
    ['GET',    'messages/recipients',                [Messages::class, 'recipients'],              'user'],
    ['DELETE', 'messages/{id}',                      [Messages::class, 'destroy'],                 'user'],
    ['POST',   'messages/{id}/reaction',             [Messages::class, 'react'],                   'user'],
    ['DELETE', 'messages/{id}/reaction',             [Messages::class, 'unreact'],                 'user'],
    ['POST',   'messages/{id}/hide',                 [Messages::class, 'hide'],                    'user'],
    ['POST',   'messages/{id}/pin',                  [Messages::class, 'pin'],                     'user'],
    ['DELETE', 'messages/{id}/pin',                  [Messages::class, 'unpin'],                   'user'],
    ['POST',   'messages/{id}/forward',              [Messages::class, 'forward'],                 'user'],

    // Historias
    ['GET',    'stories',                            [Stories::class, 'index'],                    'user'],
    ['POST',   'stories',                            [Stories::class, 'create'],                   'user'],
    ['DELETE', 'stories/{id}',                       [Stories::class, 'destroy'],                  'user'],
    ['POST',   'stories/{id}/view',                  [Stories::class, 'view'],                     'user'],
    ['GET',    'stories/{id}/viewers',               [Stories::class, 'viewers'],                  'user'],
    ['POST',   'stories/{id}/reply',                 [Stories::class, 'reply'],                    'user'],
    ['POST',   'stories/{id}/poll',                  [Stories::class, 'poll'],                     'user'],
    ['POST',   'stories/{id}/reaction',              [Stories::class, 'react'],                    'user'],
    ['DELETE', 'stories/{id}/reaction',              [Stories::class, 'react'],                    'user'],

    // Notas (6 horas) y mejores amigos
    ['GET',    'notes',                              [Notes::class, 'index'],                      'user'],
    ['POST',   'notes',                              [Notes::class, 'create'],                     'user'],
    ['DELETE', 'notes',                              [Notes::class, 'destroy'],                    'user'],
    ['POST',   'notes/{id}/reply',                   [Notes::class, 'reply'],                      'user'],
    ['GET',    'me/close-friends',                   [Notes::class, 'closeFriends'],               'user'],
    ['GET',    'me/close-friends/candidates',        [Notes::class, 'candidates'],                 'user'],
    ['POST',   'me/close-friends/{id}',              [Notes::class, 'addCloseFriend'],             'user'],
    ['DELETE', 'me/close-friends/{id}',              [Notes::class, 'removeCloseFriend'],          'user'],

    // Comunidades
    ['GET',    'communities',                        [Communities::class, 'index'],                'user'],
    ['POST',   'communities',                        [Communities::class, 'create'],               'user'],
    ['GET',    'communities/{key}',                  [Communities::class, 'show'],                 'user'],
    ['PATCH',  'communities/{id}',                   [Communities::class, 'update'],               'user'],
    ['DELETE', 'communities/{id}',                   [Communities::class, 'destroy'],              'user'],
    ['GET',    'communities/{key}/posts',            [Communities::class, 'posts'],                'user'],
    ['GET',    'communities/{key}/members',          [Communities::class, 'members'],              'user'],
    ['POST',   'communities/{id}/join',              [Communities::class, 'join'],                 'user'],
    ['DELETE', 'communities/{id}/membership',        [Communities::class, 'leave'],                'user'],
    ['POST',   'communities/{id}/requests/{id2}/approve', [Communities::class, 'resolveRequest', 'approve'], 'user'],
    ['POST',   'communities/{id}/requests/{id2}/reject',  [Communities::class, 'resolveRequest', 'reject'],  'user'],
    ['POST',   'communities/{id}/bans/{id2}',        [Communities::class, 'ban'],                  'user'],
    ['DELETE', 'communities/{id}/bans/{id2}',        [Communities::class, 'ban'],                  'user'],
    ['POST',   'communities/{id}/moderators/{id2}',  [Communities::class, 'moderator'],            'user'],
    ['DELETE', 'communities/{id}/moderators/{id2}',  [Communities::class, 'moderator'],            'user'],
    ['DELETE', 'communities/{id}/posts/{id2}',       [Communities::class, 'removePost'],           'user'],
    ['POST',   'communities/{id}/avatar',            [Communities::class, 'image', 'avatar'],      'user'],
    ['DELETE', 'communities/{id}/avatar',            [Communities::class, 'image', 'avatar'],      'user'],
    ['POST',   'communities/{id}/cover',             [Communities::class, 'image', 'cover'],       'user'],
    ['DELETE', 'communities/{id}/cover',             [Communities::class, 'image', 'cover'],       'user'],
    ['POST',   'communities/{id}/transfer',          [Communities::class, 'transfer'],             'user'],

    // Reportes
    ['POST',   'reports',                            [Reports::class, 'create'],                   'user'],

    // Moderación (moderadores y administradores)
    ['GET',    'admin/dashboard',                    [Moderation::class, 'dashboard'],             'moderator'],
    ['GET',    'admin/reports',                      [Moderation::class, 'reports'],               'moderator'],
    ['GET',    'admin/reports/{type}/{id}',          [Moderation::class, 'report'],                'moderator'],
    ['POST',   'admin/reports/{type}/{id}/take',     [Moderation::class, 'takeReports'],           'moderator'],
    ['POST',   'admin/reports/{type}/{id}/dismiss',  [Moderation::class, 'dismissReports'],        'moderator'],
    ['POST',   'admin/reports/{type}/{id}/resolve',  [Moderation::class, 'resolveReports'],        'moderator'],
    ['GET',    'admin/posts',                        [Moderation::class, 'posts'],                 'moderator'],
    ['POST',   'admin/posts/{id}/hide',              [Moderation::class, 'postAction', 'hide'],    'moderator'],
    ['POST',   'admin/posts/{id}/restore',           [Moderation::class, 'postAction', 'restore'], 'moderator'],
    ['DELETE', 'admin/posts/{id}',                   [Moderation::class, 'deletePost'],            'moderator'],
    ['POST',   'admin/posts/{id}/feature',           [Moderation::class, 'feature', true],         'admin'],
    ['DELETE', 'admin/posts/{id}/feature',           [Moderation::class, 'feature', false],        'admin'],
    ['GET',    'admin/comments',                     [Moderation::class, 'comments'],              'moderator'],
    ['DELETE', 'admin/comments/{id}',                [Moderation::class, 'deleteComment'],         'moderator'],
    ['GET',    'admin/users',                        [Moderation::class, 'users'],                 'moderator'],
    ['GET',    'admin/users/{id}',                   [Moderation::class, 'showUser'],              'moderator'],
    ['POST',   'admin/users/{id}/suspend',           [Moderation::class, 'suspend'],               'moderator'],
    ['POST',   'admin/users/{id}/unsuspend',         [Moderation::class, 'unsuspend'],             'moderator'],
    ['PUT',    'admin/users/{id}/role',              [Moderation::class, 'role'],                  'admin'],
    ['POST',   'admin/users/{id}/verification',      [Moderation::class, 'verification'],          'admin'],
    ['DELETE', 'admin/users/{id}/verification',      [Moderation::class, 'verification'],          'admin'],
    ['POST',   'admin/users/{id}/warn',              [Moderation::class, 'warn'],                  'moderator'],
    ['DELETE', 'admin/warnings/{id}',                [Moderation::class, 'revokeWarning'],         'moderator'],
    ['GET',    'admin/verification',                 [Moderation::class, 'verifications'],         'admin'],
    ['POST',   'admin/verification/{id}/approve',    [Moderation::class, 'approveVerification'],   'admin'],
    ['POST',   'admin/verification/{id}/reject',     [Moderation::class, 'rejectVerification'],    'admin'],
    ['GET',    'admin/music',                        [Music::class, 'adminList'],                  'moderator'],
    ['POST',   'admin/music/{id}/approve',           [Music::class, 'moderate', 'approve'],        'moderator'],
    ['POST',   'admin/music/{id}/reject',            [Music::class, 'moderate', 'reject'],         'moderator'],
    ['POST',   'admin/music/{id}/remove',            [Music::class, 'moderate', 'remove'],         'moderator'],
    ['POST',   'admin/music/{id}/restore',           [Music::class, 'moderate', 'restore'],        'moderator'],

    // Administración (solo administradores)
    ['GET',    'admin/communities',                  [Admin::class, 'communities'],                'admin'],
    ['POST',   'admin/communities/{id}/suspend',     [Admin::class, 'suspendCommunity'],           'admin'],
    ['POST',   'admin/communities/{id}/restore',     [Admin::class, 'restoreCommunity'],           'admin'],
    ['DELETE', 'admin/communities/{id}',             [Admin::class, 'deleteCommunity'],            'admin'],
    ['GET',    'admin/settings',                     [Admin::class, 'settings'],                   'admin'],
    ['PATCH',  'admin/settings',                     [Admin::class, 'updateSettings'],             'admin'],
    ['GET',    'admin/audit',                        [Admin::class, 'audit'],                      'admin'],
];
