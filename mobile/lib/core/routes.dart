import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/communities/community_screen.dart';
import '../screens/explore/hashtag_screen.dart';
import '../screens/messages/chat_screen.dart';
import '../screens/music/song_screen.dart';
import '../screens/post/composer_screen.dart';
import '../screens/post/post_screen.dart';
import '../screens/profile/profile_screen.dart';
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

/// Abre el compositor. Devuelve la publicación creada o editada.
Future<Post?> openComposer(BuildContext context, {Post? edit, Post? share, Community? community, String format = 'post', Song? song}) =>
    push<Post>(context, ComposerScreen(edit: edit, share: share, community: community, format: format, song: song), fullscreen: true);
