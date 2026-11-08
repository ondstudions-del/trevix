// Modelos de la API v1 (formas definidas en app/Api/Present.php). El análisis es tolerante: un campo que falta
// toma un valor vacío en lugar de romper la pantalla.

typedef Json = Map<String, dynamic>;

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) => v == null ? null : asInt(v);

bool asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String asStr(dynamic v, [String fallback = '']) => v == null ? fallback : '$v';

String? asStrOrNull(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

DateTime? asDate(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

Json asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Json? asMapOrNull(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<T> asList<T>(dynamic v, T Function(Json) parse) =>
    v is List ? v.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList() : <T>[];

class Relation {
  Relation({this.following = false, this.requested = false, this.followsYou = false});

  factory Relation.fromJson(Json j) =>
      Relation(following: asBool(j['following']), requested: asBool(j['requested']), followsYou: asBool(j['follows_you']));

  bool following;
  bool requested;
  bool followsYou;
}

class User {
  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isVerified = false,
    this.isPrivate = false,
    this.bio = '',
    this.followersCount = 0,
    this.relation,
    this.reason,
    this.website,
    this.country,
    this.coverUrl,
    this.accountType = 'personal',
    this.creatorCategory,
    this.creatorLabel,
    this.isMusicArtist = false,
    this.role = 'user',
    this.online = false,
    this.followingCount = 0,
    this.postsCount = 0,
    this.createdAt,
    this.extraDate,
  });

  factory User.fromJson(Json j) => User(
        id: asInt(j['id']),
        username: asStr(j['username']),
        displayName: asStr(j['display_name'], asStr(j['username'])),
        avatarUrl: asStrOrNull(j['avatar_url']),
        isVerified: asBool(j['is_verified']),
        isPrivate: asBool(j['is_private']),
        bio: asStr(j['bio']),
        followersCount: asInt(j['followers_count']),
        relation: j['relation'] is Map ? Relation.fromJson(asMap(j['relation'])) : null,
        reason: asStrOrNull(j['reason']),
        website: asStrOrNull(j['website']),
        country: asStrOrNull(j['country']),
        coverUrl: asStrOrNull(j['cover_url']),
        accountType: asStr(j['account_type'], 'personal'),
        creatorCategory: asStrOrNull(j['creator_category']),
        creatorLabel: asStrOrNull(j['creator_label']),
        isMusicArtist: asBool(j['is_music_artist']),
        role: asStr(j['role'], 'user'),
        online: asBool(j['online']),
        followingCount: asInt(j['following_count']),
        postsCount: asInt(j['posts_count']),
        createdAt: asDate(j['created_at']),
        extraDate: asDate(j['viewed_at'] ?? j['requested_at'] ?? j['blocked_at']),
      );

  final int id;
  String username;
  String displayName;
  String? avatarUrl;
  bool isVerified;
  bool isPrivate;
  String bio;
  int followersCount;
  Relation? relation;
  final String? reason;
  String? website;
  String? country;
  String? coverUrl;
  String accountType;
  String? creatorCategory;
  String? creatorLabel;
  bool isMusicArtist;
  String role;
  bool online;
  int followingCount;
  int postsCount;
  final DateTime? createdAt;

  /// viewed_at / requested_at / blocked_at según la lista.
  final DateTime? extraDate;

  bool get isStaffRole => role == 'moderator' || role == 'admin';
}

class Profile {
  Profile({
    required this.user,
    this.isOwn = false,
    this.isBlocked = false,
    this.canView = true,
    this.conversationId,
    this.messageBlockedReason,
    this.storiesActive = false,
    this.storiesUnseen = false,
    this.webUrl = '',
  });

  factory Profile.fromJson(Json j) {
    final message = asMap(j['message']);
    final stories = asMap(j['stories']);
    return Profile(
      user: User.fromJson(j),
      isOwn: asBool(j['is_own']),
      isBlocked: asBool(j['is_blocked']),
      canView: j['can_view'] == null ? true : asBool(j['can_view']),
      conversationId: asIntOrNull(message['conversation_id']),
      messageBlockedReason: asStrOrNull(message['blocked_reason']),
      storiesActive: asBool(stories['active']),
      storiesUnseen: asBool(stories['unseen']),
      webUrl: asStr(j['web_url']),
    );
  }

  final User user;
  final bool isOwn;
  bool isBlocked;
  final bool canView;
  final int? conversationId;
  final String? messageBlockedReason;
  final bool storiesActive;
  final bool storiesUnseen;
  final String webUrl;
}

class Counts {
  Counts({this.notifications = 0, this.followRequests = 0, this.messages = 0});

  factory Counts.fromJson(Json j) => Counts(
        notifications: asInt(j['notifications']),
        followRequests: asInt(j['follow_requests']),
        messages: asInt(j['messages']),
      );

  final int notifications;
  final int followRequests;
  final int messages;

  int get activity => notifications + followRequests;
}

class Me {
  Me({
    required this.user,
    required this.email,
    this.emailVerified = false,
    this.birthDate,
    this.isStaff = false,
    required this.settings,
    required this.counts,
  });

  factory Me.fromJson(Json j) => Me(
        user: User.fromJson(j),
        email: asStr(j['email']),
        emailVerified: asBool(j['email_verified']),
        birthDate: asStrOrNull(j['birth_date']),
        isStaff: asBool(j['is_staff']),
        settings: asMap(j['settings']),
        counts: Counts.fromJson(asMap(j['counts'])),
      );

  final User user;
  final String email;
  final bool emailVerified;
  final String? birthDate;
  final bool isStaff;
  final Json settings;
  Counts counts;

  int get id => user.id;
  String get username => user.username;
  bool get isAdmin => user.role == 'admin';
  bool setting(String key) => asBool(settings[key]);
  String get messagePrivacy => asStr(settings['message_privacy'], 'everyone');
}

class Media {
  Media({required this.type, required this.url, this.alt = '', this.width, this.height});

  factory Media.fromJson(Json j) => Media(
        type: asStr(j['type'], 'image'),
        url: asStr(j['url']),
        alt: asStr(j['alt']),
        width: asIntOrNull(j['width']),
        height: asIntOrNull(j['height']),
      );

  final String type;
  final String url;
  final String alt;
  final int? width;
  final int? height;

  bool get isVideo => type == 'video';

  double get aspect {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return isVideo ? 16 / 9 : 1;
    return (w / h).clamp(0.6, 1.9);
  }
}

class Song {
  Song({
    required this.id,
    this.available = true,
    this.title = '',
    this.featuring,
    this.genre = 'other',
    this.genreLabel = '',
    this.isExplicit = false,
    this.duration = 0,
    this.audioUrl = '',
    this.coverUrl,
    this.usesCount = 0,
    this.publishedAt,
    this.artist,
    this.webUrl = '',
    this.clipStart,
    this.clipEnd,
    this.source = 'trevix',
    this.sourceLabel = 'TREVIX',
    this.externalUrl,
  });

  factory Song.fromJson(Json j) {
    final clip = asMapOrNull(j['clip']);
    return Song(
      id: asInt(j['id']),
      available: j['available'] == null ? true : asBool(j['available']),
      title: asStr(j['title']),
      featuring: asStrOrNull(j['featuring']),
      genre: asStr(j['genre'], 'other'),
      genreLabel: asStr(j['genre_label']),
      isExplicit: asBool(j['is_explicit']),
      duration: asInt(j['duration']),
      audioUrl: asStr(j['audio_url']),
      coverUrl: asStrOrNull(j['cover_url']),
      usesCount: asInt(j['uses_count']),
      publishedAt: asDate(j['published_at']),
      artist: j['artist'] is Map ? User.fromJson(asMap(j['artist'])) : null,
      webUrl: asStr(j['web_url']),
      clipStart: clip == null ? null : asInt(clip['start']),
      clipEnd: clip == null ? null : asInt(clip['end']),
      source: asStr(j['source'], 'trevix'),
      sourceLabel: asStr(j['source_label'], 'TREVIX'),
      externalUrl: asStrOrNull(j['external_url']),
    );
  }

  final int id;
  final bool available;
  final String title;
  final String? featuring;
  final String genre;
  final String genreLabel;
  final bool isExplicit;
  final int duration;
  final String audioUrl;
  final String? coverUrl;
  final int usesCount;
  final DateTime? publishedAt;
  final User? artist;
  final String webUrl;
  final int? clipStart;
  final int? clipEnd;

  /// trevix (artista de la comunidad) | audius | freetouse (catálogos externos, sin perfil en TREVIX).
  final String source;
  final String sourceLabel;
  final String? externalUrl;

  bool get hasClip => clipStart != null && clipEnd != null;
  bool get isExternal => source != 'trevix';

  /// Atribución que exigen los catálogos externos.
  String get credit => source == 'freetouse'
      ? 'Música: «$title» de ${artist?.displayName ?? ''} — Free To Use (freetouse.com)'
      : 'Música de ${artist?.displayName ?? ''} en $sourceLabel';

  /// Copia con el fragmento [start, start + length] (como mucho hasta el final de la canción).
  Song withClip(int start, [int length = 30]) => Song(
        id: id,
        available: available,
        title: title,
        featuring: featuring,
        genre: genre,
        genreLabel: genreLabel,
        isExplicit: isExplicit,
        duration: duration,
        audioUrl: audioUrl,
        coverUrl: coverUrl,
        usesCount: usesCount,
        publishedAt: publishedAt,
        artist: artist,
        webUrl: webUrl,
        clipStart: start,
        clipEnd: start + length > duration ? duration : start + length,
        source: source,
        sourceLabel: sourceLabel,
        externalUrl: externalUrl,
      );

  String get artistLine {
    final name = artist?.displayName ?? '';
    final feat = featuring;
    final line = feat == null || feat.isEmpty ? name : '$name · feat. $feat';
    return isExternal ? '$line · $sourceLabel' : line;
  }
}

/// Pista de un catálogo externo (Audius o Free To Use) antes de elegirla: al usarla se importa como [Song].
class CatalogTrack {
  CatalogTrack({
    required this.source,
    required this.sourceLabel,
    required this.externalId,
    required this.title,
    this.artist = '',
    this.genreLabel = '',
    this.duration = 0,
    this.previewUrl = '',
    this.coverUrl,
    this.pageUrl,
  });

  factory CatalogTrack.fromJson(Json j) => CatalogTrack(
        source: asStr(j['source']),
        sourceLabel: asStr(j['source_label']),
        externalId: asStr(j['external_id']),
        title: asStr(j['title']),
        artist: asStr(j['artist']),
        genreLabel: asStr(j['genre_label']),
        duration: asInt(j['duration']),
        previewUrl: asStr(j['preview_url']),
        coverUrl: asStrOrNull(j['cover_url']),
        pageUrl: asStrOrNull(j['page_url']),
      );

  final String source;
  final String sourceLabel;
  final String externalId;
  final String title;
  final String artist;
  final String genreLabel;
  final int duration;
  final String previewUrl;
  final String? coverUrl;
  final String? pageUrl;

  String get playKey => 'cat:$source:$externalId';

  /// Canción provisional para escuchar la pista en el reproductor antes de importarla.
  Song get preview => Song(
        id: 0,
        title: title,
        duration: duration,
        audioUrl: previewUrl,
        coverUrl: coverUrl,
        genreLabel: genreLabel,
        source: source,
        sourceLabel: sourceLabel,
      );
}

/// GIF o sticker de GIPHY (en comentarios y mensajes).
class Gif {
  Gif({required this.id, this.kind = 'gif', required this.url, this.width = 0, this.height = 0, this.title = ''});

  factory Gif.fromJson(Json j) => Gif(
        id: asStr(j['id']),
        kind: asStr(j['kind'], 'gif'),
        url: asStr(j['url']),
        width: asInt(j['width']),
        height: asInt(j['height']),
        title: asStr(j['title']),
      );

  static Gif? maybe(dynamic v) {
    if (v is! Map) return null;
    final gif = Gif.fromJson(asMap(v));
    return gif.url.isEmpty ? null : gif;
  }

  final String id;
  final String kind;
  final String url;
  final int width;
  final int height;
  final String title;

  bool get isSticker => kind == 'sticker';
  double get aspect => width > 0 && height > 0 ? (width / height).clamp(0.4, 2.5).toDouble() : 1;
}

/// Nota de voz de un mensaje.
class VoiceNote {
  VoiceNote({required this.url, this.duration = 0});

  static VoiceNote? maybe(dynamic v) {
    if (v is! Map) return null;
    final url = asStr(v['url']);
    return url.isEmpty ? null : VoiceNote(url: url, duration: asInt(v['duration']));
  }

  final String url;
  final int duration;
}

class OwnSong {
  OwnSong({
    required this.id,
    required this.title,
    this.featuring,
    this.genreLabel = '',
    this.isExplicit = false,
    this.status = 'pending',
    this.statusLabel = '',
    this.duration = 0,
    this.sizeBytes = 0,
    this.audioUrl = '',
    this.coverUrl,
    this.reviewNote,
    this.createdAt,
    this.publishedAt,
    this.usesTotal = 0,
    this.usesPosts = 0,
    this.usesStories = 0,
    this.usesMessages = 0,
    this.actions = const [],
  });

  factory OwnSong.fromJson(Json j) {
    final uses = asMap(j['uses']);
    return OwnSong(
      id: asInt(j['id']),
      title: asStr(j['title']),
      featuring: asStrOrNull(j['featuring']),
      genreLabel: asStr(j['genre_label']),
      isExplicit: asBool(j['is_explicit']),
      status: asStr(j['status'], 'pending'),
      statusLabel: asStr(j['status_label']),
      duration: asInt(j['duration']),
      sizeBytes: asInt(j['size_bytes']),
      audioUrl: asStr(j['audio_url']),
      coverUrl: asStrOrNull(j['cover_url']),
      reviewNote: asStrOrNull(j['review_note']),
      createdAt: asDate(j['created_at']),
      publishedAt: asDate(j['published_at']),
      usesTotal: asInt(uses['total']),
      usesPosts: asInt(uses['posts']),
      usesStories: asInt(uses['stories']),
      usesMessages: asInt(uses['messages']),
      actions: j['actions'] is List ? (j['actions'] as List).map((e) => '$e').toList() : const [],
    );
  }

  final int id;
  final String title;
  final String? featuring;
  final String genreLabel;
  final bool isExplicit;
  final String status;
  final String statusLabel;
  final int duration;
  final int sizeBytes;
  final String audioUrl;
  final String? coverUrl;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? publishedAt;
  final int usesTotal;
  final int usesPosts;
  final int usesStories;
  final int usesMessages;
  final List<String> actions;
}

class PostCommunity {
  PostCommunity({required this.id, required this.slug, required this.name, this.canModerate = false});

  factory PostCommunity.fromJson(Json j) =>
      PostCommunity(id: asInt(j['id']), slug: asStr(j['slug']), name: asStr(j['name']), canModerate: asBool(j['can_moderate']));

  final int id;
  final String slug;
  final String name;
  final bool canModerate;
}

class Post {
  Post({
    required this.id,
    required this.format,
    required this.body,
    required this.visibility,
    required this.createdAt,
    required this.isEdited,
    required this.user,
    this.community,
    this.media = const [],
    this.song,
    this.shared,
    this.sharedUnavailable = false,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.liked = false,
    this.saved = false,
    this.isAuthor = false,
    this.webUrl = '',
  });

  factory Post.fromJson(Json j) {
    final counts = asMap(j['counts']);
    final viewer = asMap(j['viewer']);
    return Post(
      id: asInt(j['id']),
      format: asStr(j['format'], 'post'),
      body: asStr(j['body']),
      visibility: asStr(j['visibility'], 'public'),
      createdAt: asDate(j['created_at']),
      isEdited: asBool(j['is_edited']),
      user: User.fromJson(asMap(j['user'])),
      community: j['community'] is Map ? PostCommunity.fromJson(asMap(j['community'])) : null,
      media: asList(j['media'], Media.fromJson),
      song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
      shared: j['shared'] is Map ? Post.fromJson(asMap(j['shared'])) : null,
      sharedUnavailable: asBool(j['shared_unavailable']),
      likes: asInt(counts['likes']),
      comments: asInt(counts['comments']),
      shares: asInt(counts['shares']),
      saves: asInt(counts['saves']),
      liked: asBool(viewer['liked']),
      saved: asBool(viewer['saved']),
      isAuthor: asBool(viewer['is_author']),
      webUrl: asStr(j['web_url']),
    );
  }

  final int id;
  final String format;
  final String body;
  final String visibility;
  final DateTime? createdAt;
  final bool isEdited;
  final User user;
  final PostCommunity? community;
  final List<Media> media;
  final Song? song;
  final Post? shared;
  final bool sharedUnavailable;
  int likes;
  int comments;
  int shares;
  int saves;
  bool liked;
  bool saved;
  final bool isAuthor;
  final String webUrl;

  bool get isThread => format == 'thread';
  bool get isShare => shared != null || sharedUnavailable;
}

class Comment {
  Comment({
    required this.id,
    required this.postId,
    this.parentId,
    required this.body,
    this.createdAt,
    required this.user,
    this.repliesCount = 0,
    List<Comment>? replies,
    this.canDelete = false,
    this.gif,
  }) : replies = replies ?? [];

  factory Comment.fromJson(Json j) => Comment(
        id: asInt(j['id']),
        postId: asInt(j['post_id']),
        parentId: asIntOrNull(j['parent_id']),
        body: asStr(j['body']),
        gif: Gif.maybe(j['gif']),
        createdAt: asDate(j['created_at']),
        user: User.fromJson(asMap(j['user'])),
        repliesCount: asInt(j['replies_count']),
        replies: asList(j['replies'], Comment.fromJson),
        canDelete: asBool(j['can_delete']),
      );

  final int id;
  final int postId;
  final int? parentId;
  final String body;
  final DateTime? createdAt;
  final User user;
  int repliesCount;
  final List<Comment> replies;
  final bool canDelete;
  final Gif? gif;
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.type,
    this.actor,
    this.text = '',
    this.excerpt,
    this.thumbUrl,
    this.postId,
    this.songId,
    this.commentId,
    this.communityId,
    this.read = false,
    this.createdAt,
  });

  factory NotificationItem.fromJson(Json j) => NotificationItem(
        id: asInt(j['id']),
        type: asStr(j['type']),
        actor: j['actor'] is Map ? User.fromJson(asMap(j['actor'])) : null,
        text: asStr(j['text']),
        excerpt: asStrOrNull(j['excerpt']),
        thumbUrl: asStrOrNull(j['thumb_url']),
        postId: asIntOrNull(j['post_id']),
        songId: asIntOrNull(j['song_id']),
        commentId: asIntOrNull(j['comment_id']),
        communityId: asIntOrNull(j['community_id']),
        read: asBool(j['read']),
        createdAt: asDate(j['created_at']),
      );

  final int id;
  final String type;
  final User? actor;
  final String text;
  final String? excerpt;
  final String? thumbUrl;
  final int? postId;
  final int? songId;
  final int? commentId;
  final int? communityId;
  bool read;
  final DateTime? createdAt;

  bool get isMusic => type.startsWith('song_');
}

class Conversation {
  Conversation({
    required this.id,
    required this.user,
    this.available = true,
    this.blocked = false,
    this.online = false,
    this.unread = 0,
    this.muted = false,
    this.preview = '',
    this.lastMessageAt,
    this.partnerLastReadId = 0,
    this.blockedReason,
  });

  factory Conversation.fromJson(Json j) => Conversation(
        id: asInt(j['id']),
        user: User.fromJson(asMap(j['user'])),
        available: j['available'] == null ? true : asBool(j['available']),
        blocked: asBool(j['blocked']),
        online: asBool(j['online']),
        unread: asInt(j['unread']),
        muted: asBool(j['muted']),
        preview: asStr(j['preview']),
        lastMessageAt: asDate(j['last_message_at']),
        partnerLastReadId: asInt(j['partner_last_read_id']),
        blockedReason: asStrOrNull(j['blocked_reason']),
      );

  final int id;
  final User user;
  final bool available;
  final bool blocked;
  bool online;
  int unread;
  bool muted;
  final String preview;
  final DateTime? lastMessageAt;
  int partnerLastReadId;
  final String? blockedReason;
}

class StoryRef {
  StoryRef({required this.id, this.expired = false, this.type, this.mediaUrl, this.body = '', this.background});

  factory StoryRef.fromJson(Json j) => StoryRef(
        id: asInt(j['id']),
        expired: asBool(j['expired']),
        type: asStrOrNull(j['type']),
        mediaUrl: asStrOrNull(j['media_url']),
        body: asStr(j['body']),
        background: asStrOrNull(j['background']),
      );

  final int id;
  final bool expired;
  final String? type;
  final String? mediaUrl;
  final String body;
  final String? background;
}

class Message {
  Message({
    required this.id,
    required this.conversationId,
    this.senderId,
    this.isMine = false,
    this.body,
    this.imageUrl,
    this.voice,
    this.gif,
    this.song,
    this.deleted = false,
    this.story,
    this.createdAt,
  });

  factory Message.fromJson(Json j) => Message(
        id: asInt(j['id']),
        conversationId: asInt(j['conversation_id']),
        senderId: asIntOrNull(j['sender_id']),
        isMine: asBool(j['is_mine']),
        body: asStrOrNull(j['body']),
        imageUrl: asStrOrNull(j['image_url']),
        voice: VoiceNote.maybe(j['voice']),
        gif: Gif.maybe(j['gif']),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        deleted: asBool(j['deleted']),
        story: j['story'] is Map ? StoryRef.fromJson(asMap(j['story'])) : null,
        createdAt: asDate(j['created_at']),
      );

  final int id;
  final int conversationId;
  final int? senderId;
  final bool isMine;
  String? body;
  String? imageUrl;
  VoiceNote? voice;
  Gif? gif;

  /// Solo en mensajes antiguos: los chats ya no envían música.
  Song? song;
  bool deleted;
  final StoryRef? story;
  final DateTime? createdAt;

  void markDeleted() {
    deleted = true;
    body = null;
    imageUrl = null;
    voice = null;
    gif = null;
    song = null;
  }
}

class StoryItem {
  StoryItem({
    required this.id,
    required this.type,
    this.mediaUrl,
    this.mime,
    this.body = '',
    this.background,
    this.song,
    this.seconds = 6,
    this.views,
    this.seen = false,
    this.createdAt,
  });

  factory StoryItem.fromJson(Json j) => StoryItem(
        id: asInt(j['id']),
        type: asStr(j['type'], 'image'),
        mediaUrl: asStrOrNull(j['media_url']),
        mime: asStrOrNull(j['mime']),
        body: asStr(j['body']),
        background: asStrOrNull(j['background']),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        seconds: asInt(j['seconds'], 6),
        views: asIntOrNull(j['views']),
        seen: asBool(j['seen']),
        createdAt: asDate(j['created_at']),
      );

  final int id;
  final String type;
  final String? mediaUrl;
  final String? mime;
  final String body;
  final String? background;
  final Song? song;
  final int seconds;
  int? views;
  bool seen;
  final DateTime? createdAt;

  bool get isVideo => type == 'video';
  bool get isText => type == 'text';
}

class StoryGroup {
  StoryGroup({required this.user, this.own = false, this.replyBlocked, required this.items});

  factory StoryGroup.fromJson(Json j) => StoryGroup(
        user: User.fromJson(asMap(j['user'])),
        own: asBool(j['own']),
        replyBlocked: asStrOrNull(j['reply_blocked']),
        items: asList(j['items'], StoryItem.fromJson),
      );

  final User user;
  final bool own;
  final String? replyBlocked;
  final List<StoryItem> items;

  bool get hasUnseen => items.any((i) => !i.seen);

  int get firstUnseen {
    final i = items.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }
}

class CommunityAccess {
  CommunityAccess({
    this.member = false,
    this.owner = false,
    this.manager = false,
    this.banned = false,
    this.pending = false,
    this.canView = false,
    this.canPost = false,
  });

  factory CommunityAccess.fromJson(Json j) => CommunityAccess(
        member: asBool(j['member']),
        owner: asBool(j['owner']),
        manager: asBool(j['manager']),
        banned: asBool(j['banned']),
        pending: asBool(j['pending']),
        canView: asBool(j['can_view']),
        canPost: asBool(j['can_post']),
      );

  final bool member;
  final bool owner;
  final bool manager;
  final bool banned;
  final bool pending;
  final bool canView;
  final bool canPost;
}

class Community {
  Community({
    required this.id,
    required this.slug,
    required this.name,
    this.description = '',
    this.category = '',
    this.avatarUrl,
    this.coverUrl,
    this.visibility = 'public',
    this.membersCount = 0,
    this.postsCount = 0,
    this.createdAt,
    this.role,
    this.status,
    this.ownerUsername,
    this.ownerName,
    this.access,
    this.pendingRequests = 0,
    this.webUrl = '',
  });

  factory Community.fromJson(Json j) {
    final membership = asMapOrNull(j['membership']);
    final owner = asMapOrNull(j['owner']);
    return Community(
      id: asInt(j['id']),
      slug: asStr(j['slug']),
      name: asStr(j['name']),
      description: asStr(j['description']),
      category: asStr(j['category']),
      avatarUrl: asStrOrNull(j['avatar_url']),
      coverUrl: asStrOrNull(j['cover_url']),
      visibility: asStr(j['visibility'], 'public'),
      membersCount: asInt(j['members_count']),
      postsCount: asInt(j['posts_count']),
      createdAt: asDate(j['created_at']),
      role: membership == null ? null : asStrOrNull(membership['role']),
      status: membership == null ? null : asStrOrNull(membership['status']),
      ownerUsername: owner == null ? null : asStrOrNull(owner['username']),
      ownerName: owner == null ? null : asStrOrNull(owner['display_name']),
      access: j['access'] is Map ? CommunityAccess.fromJson(asMap(j['access'])) : null,
      pendingRequests: asInt(j['pending_requests']),
      webUrl: asStr(j['web_url']),
    );
  }

  final int id;
  final String slug;
  final String name;
  final String description;
  final String category;
  final String? avatarUrl;
  final String? coverUrl;
  final String visibility;
  final int membersCount;
  final int postsCount;
  final DateTime? createdAt;
  final String? role;
  final String? status;
  final String? ownerUsername;
  final String? ownerName;
  final CommunityAccess? access;
  final int pendingRequests;
  final String webUrl;

  bool get isPrivate => visibility == 'private';
  bool get isMember => status == 'active';
}

class Hashtag {
  Hashtag({required this.tag, this.category, this.postsCount = 0});

  factory Hashtag.fromJson(Json j) =>
      Hashtag(tag: asStr(j['tag']), category: asStrOrNull(j['category']), postsCount: asInt(j['posts_count']));

  final String tag;
  final String? category;
  final int postsCount;
}

class Member {
  Member({required this.user, this.role = 'member', this.status = 'active'});

  factory Member.fromJson(Json j) => Member(user: User.fromJson(j), role: asStr(j['role'], 'member'), status: asStr(j['status'], 'active'));

  final User user;
  final String role;
  final String status;
}

class SessionItem {
  SessionItem({required this.id, required this.name, this.current = false, this.lastUsedAt, this.lastIp, this.createdAt});

  factory SessionItem.fromJson(Json j) => SessionItem(
        id: asInt(j['id']),
        name: asStr(j['name'], 'Dispositivo'),
        current: asBool(j['current']),
        lastUsedAt: asDate(j['last_used_at']),
        lastIp: asStrOrNull(j['last_ip']),
        createdAt: asDate(j['created_at']),
      );

  final int id;
  final String name;
  final bool current;
  final DateTime? lastUsedAt;
  final String? lastIp;
  final DateTime? createdAt;
}
