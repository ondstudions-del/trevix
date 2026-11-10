// Modelos de la API v1 (formas definidas en app/Api/Present.php). El análisis es tolerante: un campo que falta
// toma un valor vacío en lugar de romper la pantalla.

import 'dart:math' as math;

import '../core/e2ee.dart' show E2eePayload;

typedef Json = Map<String, dynamic>;

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic v) => v == null ? null : asInt(v);

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

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
    this.details,
    this.note,
  });

  factory Profile.fromJson(Json j) {
    final message = asMap(j['message']);
    final stories = asMap(j['stories']);
    return Profile(
      details: j['details'] is Map ? ProfileDetails.fromJson(asMap(j['details'])) : null,
      user: User.fromJson(j),
      isOwn: asBool(j['is_own']),
      isBlocked: asBool(j['is_blocked']),
      canView: j['can_view'] == null ? true : asBool(j['can_view']),
      conversationId: asIntOrNull(message['conversation_id']),
      messageBlockedReason: asStrOrNull(message['blocked_reason']),
      storiesActive: asBool(stories['active']),
      storiesUnseen: asBool(stories['unseen']),
      webUrl: asStr(j['web_url']),
      note: Note.maybe(j['note']),
    );
  }

  /// Nota de 6 horas visible para quien mira (la propia en el perfil propio).
  Note? note;

  final User user;
  final bool isOwn;
  bool isBlocked;
  final bool canView;
  final int? conversationId;
  final String? messageBlockedReason;
  final bool storiesActive;
  final bool storiesUnseen;
  final String webUrl;

  /// Datos personales que esa persona deja ver a quien mira (null si está bloqueada).
  ProfileDetails? details;
}

class ProfileLink {
  ProfileLink({required this.title, required this.url});

  factory ProfileLink.fromJson(Json j) => ProfileLink(title: asStr(j['title']), url: asStr(j['url']));

  final String title;
  final String url;

  Json toJson() => {'title': title, 'url': url};
}

class ProfileContact {
  ProfileContact({required this.type, required this.value, this.label = '', this.url});

  factory ProfileContact.fromJson(Json j) =>
      ProfileContact(type: asStr(j['type']), value: asStr(j['value']), label: asStr(j['label']), url: asStrOrNull(j['url']));

  final String type;
  final String value;
  final String label;
  final String? url;

  Json toJson() => {'type': type, 'value': value};
}

/// Datos personales del perfil (GET me/details y el campo «details» de users/{username}). Lo que no se
/// puede ver según el público elegido llega como null.
class ProfileDetails {
  ProfileDetails({
    this.city,
    this.hometown,
    this.relationshipStatus,
    this.relationshipLabel,
    this.gender,
    this.genderLabel,
    this.birthDay,
    this.birthMonth,
    this.birthYear,
    this.interests = const [],
    this.links = const [],
    this.contacts = const [],
    this.song,
    this.audience,
    this.showBirthYear = false,
  });

  factory ProfileDetails.fromJson(Json j) {
    final birthday = asMapOrNull(j['birthday']);
    return ProfileDetails(
      city: asStrOrNull(j['city']),
      hometown: asStrOrNull(j['hometown']),
      relationshipStatus: asStrOrNull(j['relationship_status']),
      relationshipLabel: asStrOrNull(j['relationship_label']),
      gender: asStrOrNull(j['gender']),
      genderLabel: asStrOrNull(j['gender_label']),
      birthDay: birthday == null ? null : asIntOrNull(birthday['day']),
      birthMonth: birthday == null ? null : asIntOrNull(birthday['month']),
      birthYear: birthday == null ? null : asIntOrNull(birthday['year']),
      interests: j['interests'] is List ? (j['interests'] as List).map((e) => '$e').toList() : const [],
      links: asList(j['links'], ProfileLink.fromJson),
      contacts: asList(j['contacts'], ProfileContact.fromJson),
      song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
      audience: asStrOrNull(j['details_audience']),
      showBirthYear: asBool(j['show_birth_year']),
    );
  }

  final String? city;
  final String? hometown;
  final String? relationshipStatus;
  final String? relationshipLabel;
  final String? gender;
  final String? genderLabel;
  final int? birthDay;
  final int? birthMonth;
  final int? birthYear;
  final List<String> interests;
  final List<ProfileLink> links;
  final List<ProfileContact> contacts;
  Song? song;

  /// Solo en la propia cuenta: quién ve los datos personales y si se muestra el año de nacimiento.
  final String? audience;
  final bool showBirthYear;

  bool get hasBirthday => birthDay != null && birthMonth != null;

  bool get hasAbout =>
      city != null || hometown != null || relationshipLabel != null || genderLabel != null || hasBirthday || contacts.isNotEmpty;
}

/// Opción de un selector (clave de la API y su etiqueta en español).
class Choice {
  const Choice(this.key, this.label);

  factory Choice.fromJson(Json j) => Choice(asStr(j['key']), asStr(j['label']));

  final String key;
  final String label;
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
  Media({required this.type, required this.url, this.alt = '', this.width, this.height, this.posterUrl, this.duration});

  factory Media.fromJson(Json j) => Media(
        type: asStr(j['type'], 'image'),
        url: asStr(j['url']),
        alt: asStr(j['alt']),
        width: asIntOrNull(j['width']),
        height: asIntOrNull(j['height']),
        posterUrl: asStrOrNull(j['poster_url']),
        duration: asIntOrNull(j['duration']),
      );

  final String type;
  final String url;
  final String alt;
  final int? width;
  final int? height;
  /// Miniatura del video (los videos antiguos no la tienen: se usa su primer fotograma).
  final String? posterUrl;
  /// Duración del video en segundos, si se conoce.
  final int? duration;

  bool get isVideo => type == 'video';
  bool get isPortrait => width != null && height != null && height! > width!;

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

/// Elemento del catálogo único (music/browse): una canción que ya se puede usar o una pista externa por importar.
class CatalogEntry {
  CatalogEntry({required this.source, this.song, this.track});

  factory CatalogEntry.fromJson(Json j) => CatalogEntry(
        source: asStr(j['source'], 'trevix'),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        track: j['track'] is Map ? CatalogTrack.fromJson(asMap(j['track'])) : null,
      );

  final String source;
  final Song? song;
  final CatalogTrack? track;

  String get key => song != null ? 'song:${song!.id}' : 'cat:$source:${track?.externalId}';
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

/// Evento publicado: portada, fecha, lugar y respuestas «Asistiré» / «Me interesa».
class EventInfo {
  EventInfo({
    required this.id,
    required this.title,
    this.description = '',
    this.place = '',
    this.startsAt,
    this.endsAt,
    this.coverUrl,
    this.going = 0,
    this.interested = 0,
    this.response,
    this.isPast = false,
    this.isOwner = false,
  });

  factory EventInfo.fromJson(Json j) => EventInfo(
        id: asInt(j['id']),
        title: asStr(j['title']),
        description: asStr(j['description']),
        place: asStr(j['place']),
        startsAt: asDate(j['starts_at']),
        endsAt: asDate(j['ends_at']),
        coverUrl: asStrOrNull(j['cover_url']),
        going: asInt(j['going_count']),
        interested: asInt(j['interested_count']),
        response: asStrOrNull(j['viewer_response']),
        isPast: asBool(j['is_past']),
        isOwner: asBool(j['is_owner']),
      );

  final int id;
  final String title;
  final String description;
  final String place;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? coverUrl;
  int going;
  int interested;
  String? response;
  final bool isPast;
  final bool isOwner;
}

/// Acontecimiento importante (nuevo trabajo, mudanza…): clave, texto e icono del servidor.
class LifeEvent {
  LifeEvent({required this.key, required this.label});

  static LifeEvent? maybe(dynamic v) =>
      v is Map ? LifeEvent(key: asStr(v['key']), label: asStr(v['label'])) : null;

  final String key;
  final String label;
}

/// Lugar elegido al publicar (coordenadas redondeadas a ~100 m).
class PostPlace {
  PostPlace({required this.name, this.lat, this.lng});

  static PostPlace? maybe(dynamic v) {
    if (v is! Map || asStr(v['name']).isEmpty) return null;
    final lat = v['lat'], lng = v['lng'];
    return PostPlace(name: asStr(v['name']), lat: lat is num ? lat.toDouble() : null, lng: lng is num ? lng.toDouble() : null);
  }

  final String name;
  final double? lat;
  final double? lng;
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
    this.background,
    this.lifeEvent,
    this.place,
    this.gif,
    this.event,
    this.featured = false,
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
      background: asStrOrNull(j['background']),
      lifeEvent: LifeEvent.maybe(j['life_event']),
      place: PostPlace.maybe(j['location']),
      gif: Gif.maybe(j['gif']),
      event: j['event'] is Map ? EventInfo.fromJson(asMap(j['event'])) : null,
      featured: asBool(j['featured']),
    );
  }

  final String? background;
  final LifeEvent? lifeEvent;
  final PostPlace? place;
  final Gif? gif;
  final EventInfo? event;
  bool featured;

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
    this.searchMatch,
    this.nickname,
    this.wallpaper = 'default',
    this.disappearSeconds = 0,
    this.pinned = const [],
    this.options,
    this.blockedByMe = false,
    this.type = 'direct',
    this.theme = 'trevix',
    this.e2ee = false,
    this.keyEpoch = 0,
    this.group,
    this.readStates = const [],
  });

  factory Conversation.fromJson(Json j) => Conversation(
        type: asStrOrNull(j['type']) ?? 'direct',
        theme: asStrOrNull(j['theme']) ?? 'trevix',
        e2ee: asBool(j['e2ee']),
        keyEpoch: asInt(j['key_epoch']),
        group: j['group'] is Map ? GroupInfo.fromJson(asMap(j['group'])) : null,
        readStates: asList(j['read_states'], ReadState.fromJson),
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
        searchMatch: asStrOrNull(j['search_match']),
        nickname: asStrOrNull(j['nickname']),
        wallpaper: asStrOrNull(j['wallpaper']) ?? 'default',
        disappearSeconds: asInt(j['disappear_seconds']),
        pinned: asList(j['pinned'], Message.fromJson),
        options: j['options'] is Map ? ChatOptions.fromJson(asMap(j['options'])) : null,
        blockedByMe: asBool(j['blocked_by_me']),
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

  /// Texto del último mensaje que coincide con la búsqueda de chats.
  final String? searchMatch;

  /// Apodo de la otra persona (solo lo ve quien lo puso).
  String? nickname;
  String wallpaper;
  int disappearSeconds;
  List<Message> pinned;
  final ChatOptions? options;

  /// Quien mira bloqueó a la otra persona (solo en el detalle de la conversación).
  final bool blockedByMe;

  /// «direct» o «group». En los grupos [user] es un usuario ficticio (id 0) con el nombre y la foto del grupo.
  final String type;

  /// Estilo del chat (colores de las burbujas), compartido por todos los participantes.
  String theme;

  /// Cifrado de extremo a extremo activo y época vigente de la clave.
  bool e2ee;
  int keyEpoch;
  GroupInfo? group;

  /// En los grupos: hasta dónde leyó cada participante (solo en el detalle).
  List<ReadState> readStates;

  bool get isGroup => type == 'group';

  String get title => isGroup
      ? (group?.title ?? user.displayName)
      : (nickname ?? '').isNotEmpty
          ? nickname!
          : user.displayName;
}

/// Datos del grupo para quien mira (el enlace de invitación solo llega a quien lo puede compartir).
class GroupInfo {
  GroupInfo({
    required this.title,
    this.description = '',
    this.avatarUrl,
    this.coverUrl,
    this.visibility = 'private',
    this.role = 'member',
    this.isAdmin = false,
    this.membersCount = 0,
    this.inviteUrl,
    this.inviteCode,
  });

  factory GroupInfo.fromJson(Json j) => GroupInfo(
        title: asStr(j['title']),
        description: asStr(j['description']),
        avatarUrl: asStrOrNull(j['avatar_url']),
        coverUrl: asStrOrNull(j['cover_url']),
        visibility: asStr(j['visibility'], 'private'),
        role: asStr(j['role'], 'member'),
        isAdmin: asBool(j['is_admin']),
        membersCount: asInt(j['members_count']),
        inviteUrl: asStrOrNull(j['invite_url']),
        inviteCode: asStrOrNull(j['invite_code']),
      );

  final String title;
  final String description;
  final String? avatarUrl;
  final String? coverUrl;
  final String visibility;
  final String role;
  final bool isAdmin;
  final int membersCount;
  final String? inviteUrl;
  final String? inviteCode;

  bool get isPublic => visibility == 'public';
  bool get isOwner => role == 'owner';
}

class ReadState {
  ReadState({required this.userId, this.displayName = '', this.avatarUrl, this.lastReadId = 0});

  factory ReadState.fromJson(Json j) => ReadState(
        userId: asInt(j['user_id']),
        displayName: asStr(j['display_name']),
        avatarUrl: asStrOrNull(j['avatar_url']),
        lastReadId: asInt(j['last_read_id']),
      );

  final int userId;
  final String displayName;
  final String? avatarUrl;
  int lastReadId;

  User get user => User(id: userId, username: '', displayName: displayName, avatarUrl: avatarUrl);
}

/// Integrante de un grupo con su rol.
class GroupMember {
  GroupMember({required this.user, this.role = 'member', this.isMe = false, this.hasKey = false, this.available = true, this.joinedAt});

  factory GroupMember.fromJson(Json j) => GroupMember(
        user: User.fromJson(j),
        role: asStr(j['role'], 'member'),
        isMe: asBool(j['is_me']),
        hasKey: asBool(j['has_key']),
        available: j['available'] == null ? true : asBool(j['available']),
        joinedAt: asDate(j['joined_at']),
      );

  final User user;
  String role;
  final bool isMe;
  final bool hasKey;
  final bool available;
  final DateTime? joinedAt;

  bool get isManager => role == 'owner' || role == 'admin';
  String get roleLabel => switch (role) { 'owner' => 'Creador', 'admin' => 'Administrador', _ => '' };
}

/// Opciones del chat que da el servidor: fondos, duraciones de los mensajes temporales y reacciones rápidas.
class ChatOptions {
  ChatOptions({
    this.wallpapers = const [],
    this.disappear = const [],
    this.reactions = const ['❤️', '😂', '😮', '😢', '😡', '👍'],
    this.maxPins = 3,
    this.maxForward = 5,
    this.nicknameMax = 40,
    this.themes = const [],
    this.viewSeconds = const [0, 3, 5, 10],
  });

  factory ChatOptions.fromJson(Json j) => ChatOptions(
        themes: asList(j['themes'], (e) => MapEntry(asStr(e['key']), asStr(e['label']))),
        viewSeconds: j['view_seconds'] is List ? (j['view_seconds'] as List).map((e) => asInt(e)).toList() : const [0, 3, 5, 10],
        wallpapers: asList(j['wallpapers'], (e) => MapEntry(asStr(e['key']), asStr(e['label']))),
        disappear: asList(j['disappear_options'], (e) => MapEntry(asInt(e['seconds']), asStr(e['label']))),
        reactions: j['reactions'] is List ? (j['reactions'] as List).map((e) => asStr(e)).where((e) => e.isNotEmpty).toList() : const [],
        maxPins: asInt(j['max_pins'], 3),
        maxForward: asInt(j['max_forward'], 5),
        nicknameMax: asInt(j['nickname_max'], 40),
      );

  final List<MapEntry<String, String>> wallpapers;
  final List<MapEntry<int, String>> disappear;
  final List<String> reactions;
  final int maxPins;
  final int maxForward;
  final int nicknameMax;
  final List<MapEntry<String, String>> themes;
  final List<int> viewSeconds;
}

/// Texto cifrado de un mensaje y la época de la clave con la que se cifró.
class MessageCipher {
  MessageCipher(this.epoch, this.ciphertext);

  static MessageCipher? maybe(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final text = asStr(j['ciphertext']);
    return text.isEmpty ? null : MessageCipher(asInt(j['epoch']), text);
  }

  final int epoch;
  final String ciphertext;
}

/// Archivo que no es público (cifrado o de visualización única): se descarga con el token.
class MessageFile {
  MessageFile({required this.url, this.size = 0, this.encrypted = false, this.mime, this.duration});

  static MessageFile? maybe(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return MessageFile(
      url: asStr(j['url']),
      size: asInt(j['size']),
      encrypted: asBool(j['encrypted']),
      mime: asStrOrNull(j['mime']),
      duration: asIntOrNull(j['duration']),
    );
  }

  final String url;
  final int size;
  final bool encrypted;
  final String? mime;
  final int? duration;
}

/// Video público de un chat sin cifrar (los de visualización única y los cifrados llegan como [MessageFile]).
class MessageVideo {
  MessageVideo({required this.url, this.mime, this.duration = 0, this.width, this.height, this.posterUrl});

  static MessageVideo? maybe(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return MessageVideo(
      url: asStr(j['url']),
      mime: asStrOrNull(j['mime']),
      duration: asInt(j['duration']),
      width: asIntOrNull(j['width']),
      height: asIntOrNull(j['height']),
      posterUrl: asStrOrNull(j['poster_url']),
    );
  }

  final String url;
  final String? mime;
  final int duration;
  final int? width;
  final int? height;
  final String? posterUrl;

  double get aspect => (width ?? 0) > 0 && (height ?? 0) > 0 ? width! / height! : 9 / 16;
}

/// Foto o video de visualización única: [seconds] null = hasta cerrarla. [opened]: lo abrieron todos.
class ViewOnce {
  ViewOnce({this.seconds, this.viewed = false, this.views = 0, this.opened = false});

  static ViewOnce? maybe(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return ViewOnce(seconds: asIntOrNull(j['seconds']), viewed: asBool(j['viewed']), views: asInt(j['views']), opened: asBool(j['opened']));
  }

  final int? seconds;
  bool viewed;
  int views;
  bool opened;

  String get label => seconds == null || seconds == 0 ? '1 vez' : '${seconds}s';
}

class MessageReply {
  MessageReply({required this.id, this.senderId, this.senderName = '', this.isMine = false, this.text = '', this.available = true, this.cipher});

  factory MessageReply.fromJson(Json j) => MessageReply(
        id: asInt(j['id']),
        senderId: asIntOrNull(j['sender_id']),
        senderName: asStr(j['sender_name']),
        isMine: asBool(j['is_mine']),
        text: asStr(j['text']),
        available: asBool(j['available']),
        cipher: MessageCipher.maybe(j['e2ee']),
      );

  final int id;
  final int? senderId;
  final String senderName;
  final bool isMine;

  /// Con [cipher], la app pone aquí el resumen descifrado.
  String text;
  final bool available;
  final MessageCipher? cipher;
}

class MessageLocation {
  MessageLocation({required this.lat, required this.lng, this.name});

  static MessageLocation? maybe(Object? v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return MessageLocation(lat: asDouble(j['lat']), lng: asDouble(j['lng']), name: asStrOrNull(j['name']));
  }

  final double lat;
  final double lng;
  final String? name;
}

class Reaction {
  Reaction(this.emoji, this.count);

  final String emoji;
  final int count;
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
    this.video,
    this.voice,
    this.gif,
    this.song,
    this.deleted = false,
    this.story,
    this.createdAt,
    this.kind = 'message',
    this.systemText,
    this.reply,
    this.forwarded = false,
    this.location,
    this.pinned = false,
    this.reactions = const [],
    this.myReaction,
    this.expiresAt,
    this.context,
    this.noteText,
    this.sender,
    this.cipher,
    this.file,
    this.viewOnce,
    this.mediaCleared = false,
  });

  factory Message.fromJson(Json j) => Message(
        sender: j['sender'] is Map ? User.fromJson(asMap(j['sender'])) : null,
        cipher: MessageCipher.maybe(j['e2ee']),
        file: MessageFile.maybe(j['file']),
        viewOnce: ViewOnce.maybe(j['view_once']),
        mediaCleared: asBool(j['media_cleared']),
        id: asInt(j['id']),
        conversationId: asInt(j['conversation_id']),
        senderId: asIntOrNull(j['sender_id']),
        isMine: asBool(j['is_mine']),
        body: asStrOrNull(j['body']),
        imageUrl: asStrOrNull(j['image_url']),
        video: MessageVideo.maybe(j['video']),
        voice: VoiceNote.maybe(j['voice']),
        gif: Gif.maybe(j['gif']),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        deleted: asBool(j['deleted']),
        story: j['story'] is Map ? StoryRef.fromJson(asMap(j['story'])) : null,
        createdAt: asDate(j['created_at']),
        kind: asStrOrNull(j['kind']) ?? 'message',
        systemText: asStrOrNull(j['system_text']),
        reply: j['reply_to'] is Map ? MessageReply.fromJson(asMap(j['reply_to'])) : null,
        forwarded: asBool(j['forwarded']),
        location: MessageLocation.maybe(j['location']),
        pinned: asBool(j['pinned']),
        reactions: asList(j['reactions'], (e) => Reaction(asStr(e['emoji']), asInt(e['count'], 1))),
        myReaction: asStrOrNull(j['my_reaction']),
        expiresAt: asDate(j['expires_at']),
        context: asStrOrNull(j['context']),
        noteText: asStrOrNull(j['note_text']),
      );

  final int id;
  final int conversationId;
  final int? senderId;
  final bool isMine;
  String? body;
  String? imageUrl;
  MessageVideo? video;
  VoiceNote? voice;
  Gif? gif;

  /// Solo en mensajes antiguos: los chats ya no envían música.
  Song? song;
  bool deleted;
  final StoryRef? story;
  final DateTime? createdAt;

  /// «system»: aviso dentro del chat (p. ej. mensajes temporales activados), con su texto en [systemText].
  final String kind;
  final String? systemText;
  final MessageReply? reply;
  final bool forwarded;
  MessageLocation? location;
  bool pinned;
  List<Reaction> reactions;
  String? myReaction;

  /// Mensajes temporales: cuándo desaparece.
  final DateTime? expiresAt;

  /// «story_reaction» (reacción a la historia [story], con el emoji en [body]) o «note_reply» (respuesta a la
  /// nota cuyo texto es [noteText]).
  final String? context;
  final String? noteText;

  /// Quien lo envió (nombre y foto en los grupos).
  final User? sender;

  /// Cifrado de extremo a extremo: la app lo descifra en [payload] (null si no tiene la clave de esa época).
  MessageCipher? cipher;
  E2eePayload? payload;
  bool undecryptable = false;
  MessageFile? file;
  ViewOnce? viewOnce;

  /// Quien lo envió borró el archivo para liberar espacio.
  bool mediaCleared;

  bool get isSystem => kind == 'system';
  bool get isStoryReaction => context == 'story_reaction';
  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get encrypted => cipher != null;

  /// El adjunto protegido (visualización única o cifrado) es un video.
  bool get fileIsVideo {
    final mime = file?.encrypted == true ? payload?.mime : file?.mime;
    return (mime ?? '').startsWith('video/') || payload?.type == 'video';
  }

  /// Texto visible: el descifrado en los cifrados.
  String get text => cipher != null ? (payload?.body ?? '') : (body ?? '');

  /// Texto corto para respuestas y vistas previas.
  String get summary {
    if (deleted) return 'Mensaje eliminado';
    if (viewOnce != null) {
      final what = fileIsVideo ? '🎥 Video' : '📷 Foto';
      return viewOnce!.seconds == null ? '$what de una vez' : '$what de ${viewOnce!.seconds} s';
    }
    if (cipher != null) {
      final p = payload;
      if (p == null) return '🔒 Mensaje cifrado';
      return p.summary.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (isStoryReaction) return 'Reaccionó a una historia: ${body ?? ''}';
    if ((body ?? '').isNotEmpty) return body!.replaceAll(RegExp(r'\s+'), ' ');
    if (location != null) return 'Ubicación';
    if (voice != null) return 'Nota de voz';
    if (video != null) return 'Video';
    if (imageUrl != null) return 'Foto';
    if (gif != null) return gif!.isSticker ? 'Sticker' : 'GIF';
    return 'Canción';
  }

  /// Copia los cambios que llegan del sondeo (reacciones, fijado o eliminado).
  void updateFrom(Message other) {
    reactions = other.reactions;
    myReaction = other.myReaction;
    pinned = other.pinned;
    if (other.viewOnce != null) viewOnce = other.viewOnce;
    mediaCleared = other.mediaCleared;
    if (other.mediaCleared || (other.file == null && file != null)) file = other.file;
    if (other.deleted && !deleted) markDeleted();
  }

  void markDeleted() {
    deleted = true;
    body = null;
    cipher = null;
    payload = null;
    file = null;
    viewOnce = null;
    imageUrl = null;
    video = null;
    voice = null;
    gif = null;
    song = null;
    location = null;
    pinned = false;
    reactions = const [];
    myReaction = null;
  }
}

/// Capa de una historia con foto o video. x/y es el centro en fracciones del lienzo; scale y rotation (radianes).
class StoryLayer {
  StoryLayer({
    required this.type,
    this.x = .5,
    this.y = .5,
    this.scale = 1,
    this.rotation = 0,
    this.text = '',
    this.color = '#FFFFFF',
    this.style = 'plain',
    this.gifId,
    this.url,
    this.width = 0,
    this.height = 0,
    this.name = '',
    this.question = '',
    this.options = const [],
    this.username = '',
    this.label = '',
  });

  factory StoryLayer.fromJson(Json j) => StoryLayer(
        type: asStr(j['type']),
        x: asDouble(j['x'], .5),
        y: asDouble(j['y'], .5),
        scale: asDouble(j['scale'], 1),
        rotation: asDouble(j['rotation']),
        text: asStr(j['text']),
        color: asStr(j['color'], '#FFFFFF'),
        style: asStr(j['style'], 'plain'),
        url: asStrOrNull(j['url']),
        width: asInt(j['width']),
        height: asInt(j['height']),
        name: asStr(j['name']),
        question: asStr(j['question']),
        options: j['options'] is List ? (j['options'] as List).map((o) => '$o').toList() : const [],
        username: asStr(j['username']),
        label: asStr(j['label']),
      );

  /// Límites de tamaño que acepta el servidor (StoryOverlays).
  static const minScale = .3;
  static const maxScale = 4.0;

  final String type;
  double x;
  double y;
  double scale;
  double rotation;
  String text;
  String color;
  String style;
  final String? gifId;
  final String? url;
  final int width;
  final int height;
  String name;
  String question;
  List<String> options;
  String username;
  String label;

  /// Lo que se envía al publicar (el servidor vuelve a validarlo todo).
  Json toJson() => {
        'type': type,
        'x': double.parse(x.toStringAsFixed(4)),
        'y': double.parse(y.toStringAsFixed(4)),
        'scale': double.parse(scale.clamp(minScale, maxScale).toStringAsFixed(3)),
        'rotation': double.parse(math.atan2(math.sin(rotation), math.cos(rotation)).toStringAsFixed(4)),
        if (type == 'text') ...{'text': text, 'color': color, 'style': style},
        if (type == 'sticker') 'gif_id': gifId,
        if (type == 'location') 'name': name,
        if (type == 'poll') ...{'question': question, 'options': options},
        if (type == 'mention') 'username': username,
        if (type == 'link') ...{'url': url, 'label': label},
      };
}

/// Resultados de la encuesta: counts solo llega después de votar (o en las historias propias).
class StoryPoll {
  StoryPoll({this.counts, this.total = 0, this.viewerChoice});

  static StoryPoll? maybe(dynamic v) => v is Map
      ? StoryPoll(
          counts: v['counts'] is List ? (v['counts'] as List).map((c) => asInt(c)).toList() : null,
          total: asInt(v['total']),
          viewerChoice: asIntOrNull(v['viewer_choice']),
        )
      : null;

  List<int>? counts;
  int total;
  int? viewerChoice;
}

class StoryItem {
  StoryItem({
    required this.id,
    required this.type,
    this.mediaUrl,
    this.mime,
    this.body = '',
    this.background,
    this.layers = const [],
    this.filter,
    this.poll,
    this.song,
    this.seconds = 6,
    this.views,
    this.reactions,
    this.myReaction,
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
        layers: asList(j['overlays'], StoryLayer.fromJson),
        filter: asStrOrNull(j['filter']),
        poll: StoryPoll.maybe(j['poll']),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        seconds: asInt(j['seconds'], 6),
        views: asIntOrNull(j['views']),
        reactions: asIntOrNull(j['reactions']),
        myReaction: asStrOrNull(j['my_reaction']),
        seen: asBool(j['seen']),
        createdAt: asDate(j['created_at']),
      );

  final int id;
  final String type;
  final String? mediaUrl;
  final String? mime;
  final String body;
  final String? background;
  final List<StoryLayer> layers;
  final String? filter;
  final StoryPoll? poll;
  final Song? song;
  final int seconds;
  int? views;

  /// Cuántas reacciones tiene (solo en las propias) y la de quien mira (en las ajenas).
  int? reactions;
  String? myReaction;
  bool seen;
  final DateTime? createdAt;

  bool get isVideo => type == 'video';
  bool get isText => type == 'text';
}

class StoryGroup {
  StoryGroup({required this.user, this.own = false, this.replyBlocked, this.note, required this.items});

  factory StoryGroup.fromJson(Json j) => StoryGroup(
        user: User.fromJson(asMap(j['user'])),
        own: asBool(j['own']),
        replyBlocked: asStrOrNull(j['reply_blocked']),
        note: Note.maybe(j['note']),
        items: asList(j['items'], StoryItem.fromJson),
      );

  final User user;
  final bool own;
  final String? replyBlocked;

  /// Nota de 6 horas de esa persona (si quien mira puede verla).
  Note? note;
  final List<StoryItem> items;

  bool get hasUnseen => items.any((i) => !i.seen);

  int get firstUnseen {
    final i = items.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }
}

/// Nota de 6 horas: texto corto, sticker y/o fragmento de canción que se muestra como una nube sobre el avatar.
/// [audience], [likes], [views] y [friendViews] solo llegan en la propia.
class Note {
  Note({
    required this.id,
    required this.user,
    this.own = false,
    required this.body,
    this.sticker,
    this.song,
    this.liked = false,
    this.likes,
    this.views,
    this.friendViews,
    this.audience,
    this.audienceLabel,
    this.createdAt,
    this.expiresAt,
  });

  factory Note.fromJson(Json j) => Note(
        id: asInt(j['id']),
        user: User.fromJson(asMap(j['user'])),
        own: asBool(j['own']),
        body: asStr(j['body']),
        sticker: Gif.maybe(j['sticker']),
        song: j['song'] is Map ? Song.fromJson(asMap(j['song'])) : null,
        liked: asBool(j['liked']),
        likes: asIntOrNull(j['likes']),
        views: asIntOrNull(j['views']),
        friendViews: asIntOrNull(j['friend_views']),
        audience: asStrOrNull(j['audience']),
        audienceLabel: asStrOrNull(j['audience_label']),
        createdAt: asDate(j['created_at']),
        expiresAt: asDate(j['expires_at']),
      );

  static Note? maybe(dynamic v) => v is Map ? Note.fromJson(asMap(v)) : null;

  final int id;
  final User user;
  final bool own;
  final String body;
  final Gif? sticker;
  final Song? song;
  bool liked;
  final int? likes;
  final int? views;
  final int? friendViews;
  final String? audience;
  final String? audienceLabel;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Texto corto para la nube: el de la nota o, si no tiene, la canción.
  String get label {
    if (body.isNotEmpty) return body;
    final s = song;
    if (s != null && s.available) return '♪ ${s.title}';
    return '';
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
