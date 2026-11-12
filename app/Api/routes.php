<?php
declare(strict_types=1);

use Trevix\Api\Controllers\AdminController as Admin;
use Trevix\Api\Controllers\AppController as App;
use Trevix\Api\Controllers\AuthController as AuthApi;
use Trevix\Api\Controllers\CommunityController as Communities;
use Trevix\Api\Controllers\E2eeController as E2ee;
use Trevix\Api\Controllers\GroupController as Groups;
use Trevix\Api\Controllers\EventController as Events;
use Trevix\Api\Controllers\ExploreController as Explore;
use Trevix\Api\Controllers\GeoController as Geo;
use Trevix\Api\Controllers\GiftController as Gifts;
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
use Trevix\Api\Controllers\WalletController as Wallet;

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
    ['POST',   'auth/appeal',                        [AuthApi::class, 'appeal'],                   'guest'],
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
    ['GET',    'me/appeals',                         [Me::class, 'appeals'],                       'user'],
    ['POST',   'me/appeals',                         [Me::class, 'appealWarning'],                 'user'],
    ['PUT',    'me/locale',                          [Me::class, 'locale'],                        'user'],
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

    // Monedero, colaborador y suscripciones (USD)
    ['GET',    'me/wallet',                          [Wallet::class, 'show'],                      'user'],
    ['GET',    'me/wallet/transactions',             [Wallet::class, 'transactions'],              'user'],
    ['GET',    'me/wallet/topups',                   [Wallet::class, 'topups'],                    'user'],
    ['POST',   'me/wallet/topups',                   [Wallet::class, 'requestTopup'],              'user'],
    ['DELETE', 'me/wallet/topups/{id}',              [Wallet::class, 'cancelTopup'],               'user'],
    ['POST',   'me/wallet/play-purchases',           [Wallet::class, 'playPurchase'],              'user'],
    ['GET',    'me/wallet/withdrawals',              [Wallet::class, 'withdrawals'],               'user'],
    ['POST',   'me/wallet/withdrawals',              [Wallet::class, 'requestWithdrawal'],         'user'],
    ['DELETE', 'me/wallet/withdrawals/{id}',         [Wallet::class, 'cancelWithdrawal'],          'user'],
    ['GET',    'me/collaborator',                    [Wallet::class, 'collaborator'],              'user'],
    ['PUT',    'me/collaborator',                    [Wallet::class, 'collaborator'],              'user'],
    ['POST',   'me/collaborator/pause',              [Wallet::class, 'setActive', false],          'user'],
    ['POST',   'me/collaborator/resume',             [Wallet::class, 'setActive', true],           'user'],
    ['GET',    'me/collaborator/subscribers',        [Wallet::class, 'subscribers'],               'user'],
    ['GET',    'me/subscriptions',                   [Wallet::class, 'subscriptions'],             'user'],
    ['POST',   'users/{id}/subscribe',               [Wallet::class, 'subscribe'],                 'user'],

    // Regalos (se pagan con el monedero) y campana del perfil
    ['GET',    'gifts',                              [Gifts::class, 'index'],                      'user'],
    ['POST',   'gifts/{id}/buy',                     [Gifts::class, 'buy'],                        'user'],
    ['POST',   'gifts/{id}/send',                    [Gifts::class, 'send'],                       'user'],
    ['GET',    'me/gifts/received',                  [Gifts::class, 'history', 'received'],        'user'],
    ['GET',    'me/gifts/sent',                      [Gifts::class, 'history', 'sent'],            'user'],
    ['PUT',    'users/{id}/alerts',                  [Gifts::class, 'alerts'],                     'user'],
    ['DELETE', 'users/{id}/alerts',                  [Gifts::class, 'alerts'],                     'user'],

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
    ['POST',   'posts/{id}/translation',             [Posts::class, 'translate'],                  'user'],
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
    ['POST',   'conversations/bulk',                 [Messages::class, 'bulk'],                    'user'],
    ['GET',    'conversations/{id}',                 [Messages::class, 'show'],                    'user'],
    ['POST',   'conversations/{id}/typing',          [Messages::class, 'typing'],                  'user'],
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
    ['GET',    'messages/{id}/media',                [Messages::class, 'media'],                   'user'],
    ['GET',    'messages/{id}/info',                 [Messages::class, 'info'],                    'user'],
    ['POST',   'conversations',                      [Messages::class, 'open'],                    'user'],
    ['GET',    'conversations/{id}/shared',          [Messages::class, 'shared'],                  'user'],
    ['GET',    'conversations/{id}/storage',         [Messages::class, 'storage'],                 'user'],
    ['GET',    'me/chat-storage',                    [Messages::class, 'myStorage'],               'user'],
    ['POST',   'me/chat-storage/clean',              [Messages::class, 'cleanStorage'],            'user'],

    // Cifrado de extremo a extremo de los chats
    ['GET',    'me/keys',                            [E2ee::class, 'mine'],                        'user'],
    ['PUT',    'me/keys',                            [E2ee::class, 'register'],                    'user'],
    ['PUT',    'me/keys/backup',                     [E2ee::class, 'backup'],                      'user'],
    ['POST',   'me/keys/recover',                    [E2ee::class, 'recover'],                     'user'],
    ['GET',    'conversations/{id}/keys',            [E2ee::class, 'conversation'],                'user'],
    ['POST',   'conversations/{id}/keys',            [E2ee::class, 'rotate'],                      'user'],

    // Grupos de mensajes (los mensajes usan /conversations/{id})
    ['POST',   'groups',                             [Groups::class, 'create'],                    'user'],
    ['GET',    'groups',                             [Groups::class, 'search'],                    'user'],
    ['PATCH',  'groups/{id}',                        [Groups::class, 'update'],                    'user'],
    ['POST',   'groups/{id}/avatar',                 [Groups::class, 'image', 'avatar'],           'user'],
    ['DELETE', 'groups/{id}/avatar',                 [Groups::class, 'image', 'avatar'],           'user'],
    ['POST',   'groups/{id}/cover',                  [Groups::class, 'image', 'cover'],            'user'],
    ['DELETE', 'groups/{id}/cover',                  [Groups::class, 'image', 'cover'],            'user'],
    ['GET',    'groups/{id}/members',                [Groups::class, 'members'],                   'user'],
    ['POST',   'groups/{id}/members',                [Groups::class, 'addMembers'],                'user'],
    ['DELETE', 'groups/{id}/members/{id2}',          [Groups::class, 'removeMember'],              'user'],
    ['DELETE', 'groups/{id}/membership',             [Groups::class, 'leave'],                     'user'],
    ['POST',   'groups/{id}/admins/{id2}',           [Groups::class, 'admin'],                     'user'],
    ['DELETE', 'groups/{id}/admins/{id2}',           [Groups::class, 'admin'],                     'user'],
    ['POST',   'groups/{id}/invite',                 [Groups::class, 'resetInvite'],               'user'],
    ['GET',    'groups/{id}/requests',               [Groups::class, 'requests'],                  'user'],
    ['POST',   'groups/{id}/requests/{id2}/approve', [Groups::class, 'resolve', 'approve'],        'user'],
    ['POST',   'groups/{id}/requests/{id2}/reject',  [Groups::class, 'resolve', 'reject'],         'user'],
    ['GET',    'invites/{key}',                      [Groups::class, 'invite'],                    'user'],
    ['POST',   'invites/{key}/join',                 [Groups::class, 'join'],                      'user'],

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
    ['POST',   'notes/{id}/view',                    [Notes::class, 'view'],                       'user'],
    ['POST',   'notes/{id}/like',                    [Notes::class, 'like'],                       'user'],
    ['DELETE', 'notes/{id}/like',                    [Notes::class, 'unlike'],                     'user'],
    ['GET',    'notes/{id}/activity',                [Notes::class, 'activity'],                   'user'],
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
