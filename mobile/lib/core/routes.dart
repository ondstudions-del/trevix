import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/communities/community_screen.dart';
import '../screens/explore/hashtag_screen.dart';
import '../screens/messages/chat_screen.dart';
import '../screens/messages/group_screens.dart';
import '../screens/music/song_screen.dart';
import '../screens/post/composer_screen.dart';
import '../screens/post/post_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/reels/reel_camera_screen.dart';
import '../screens/stories/story_viewer.dart';
import 'api.dart';
import 'nav.dart';

Future<void> openProfile(BuildContext context, String username) => push<void>(context, ProfileScreen(username: username));

void openPost(BuildContext context, int id, {Post? post, bool comment = false}) =>
    push(context, PostScreen(postId: id, initial: post, focusComment: comment));

/// Un evento vive en su publicación: se busca y se abre esa publicación.
Future<void> openEvent(BuildContext context, int id) async {
  try {
    final post = Post.fromJson((await api.get('events/$id')).map);
    if (context.mounted) openPost(context, post.id, post: post);
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
}

void openHashtag(BuildContext context, String tag) => push(context, HashtagScreen(tag: tag));

void openCommunity(BuildContext context, String key) => push(context, CommunityScreen(slugOrId: key));

void openSong(BuildContext context, int id, {Song? song}) => push(context, SongScreen(songId: id, initial: song));

void openChat(BuildContext context, int conversationId, {User? user}) =>
    push(context, ChatScreen(conversationId: conversationId, user: user));

/// Historias activas de una cuenta (stories.php?u=…); si ya no tiene, se abre su perfil.
Future<void> openUserStories(BuildContext context, String username) async {
  try {
    final res = await api.get('users/${Uri.encodeComponent(username)}/stories');
    if (!context.mounted) return;
    final group = res.data is Map ? StoryGroup.fromJson(res.map) : null;
    if (group == null || group.items.isEmpty) {
      openProfile(context, username);
      return;
    }
    await pushFade(context, StoryViewer(groups: [group]));
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
}

/// Enlace de invitación a un grupo (g.php?c=CÓDIGO).
void openGroupInvite(BuildContext context, String code) => push(context, InvitePreviewScreen(code: code));

/// Abre el compositor. Devuelve la publicación creada o editada.
Future<Post?> openComposer(
  BuildContext context, {
  Post? edit,
  Post? share,
  Community? community,
  String format = 'post',
  Song? song,
  bool startWithVideo = false,
}) =>
    push<Post>(
      context,
      ComposerScreen(edit: edit, share: share, community: community, format: format, song: song, startWithVideo: startWithVideo),
      fullscreen: true,
    );

/// Cámara de reels (con la galería a la izquierda del botón de grabar). Devuelve la publicación creada.
/// [song]: canción o sonido con el que se graba («Usar este sonido»).
Future<Post?> openReelCamera(BuildContext context, {Song? song}) => push<Post>(context, ReelCameraScreen(song: song), fullscreen: true);
