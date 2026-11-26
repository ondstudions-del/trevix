import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Mensajes y cabecera del chat ya cargados (memoria + disco para modo offline).
class ChatCache {
  ChatCache._();

  static const _maxChats = 32;
  static const _maxDiskChats = 12;
  static const _maxDiskMessages = 120;
  static const _diskKey = 'trevix_chats_disk_v1';
  static final _store = <int, ChatCacheEntry>{};

  static ChatCacheEntry? peek(int conversationId) => _store[conversationId];

  static void save({
    required int conversationId,
    required Conversation conversation,
    required List<Message> messages,
    required Map<String, dynamic>? older,
    required String since,
    required int seenId,
  }) {
    while (_store.length >= _maxChats) {
      final oldest = _store.entries.reduce((a, b) => a.value.loadedAt.isBefore(b.value.loadedAt) ? a : b);
      _store.remove(oldest.key);
    }
    final prev = _store[conversationId];
    _store[conversationId] = ChatCacheEntry(
      conversation: conversation,
      messages: List<Message>.from(messages),
      older: older == null ? null : Map<String, dynamic>.from(older),
      since: since,
      seenId: seenId,
      loadedAt: DateTime.now(),
      rawConversation: prev?.rawConversation,
      rawMessages: prev?.rawMessages,
    );
  }

  /// Tras una carga exitosa del API: guarda en disco para abrir el chat sin red.
  static Future<void> saveFromApi({
    required int conversationId,
    required Map<String, dynamic> conversation,
    required List<Map<String, dynamic>> messages,
    required Map<String, dynamic>? older,
    required String since,
    required int seenId,
  }) async {
    final conv = Conversation.fromJson(conversation);
    final list = messages.map(Message.fromJson).where((m) => !m.expired).toList();
    final slice = messages.length > _maxDiskMessages ? messages.sublist(messages.length - _maxDiskMessages) : messages;
    while (_store.length >= _maxChats) {
      final oldest = _store.entries.reduce((a, b) => a.value.loadedAt.isBefore(b.value.loadedAt) ? a : b);
      _store.remove(oldest.key);
    }
    _store[conversationId] = ChatCacheEntry(
      conversation: conv,
      messages: list,
      older: older == null ? null : Map<String, dynamic>.from(older),
      since: since,
      seenId: seenId,
      loadedAt: DateTime.now(),
      rawConversation: Map<String, dynamic>.from(conversation),
      rawMessages: slice.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
    await _persistDisk(conversationId, {
      'conversation': conversation,
      'messages': slice,
      if (older != null) 'older': older,
      'since': since,
      'seen_id': seenId,
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<ChatCacheEntry?> loadDisk(int conversationId) async {
    final mem = peek(conversationId);
    if (mem != null) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_diskKey);
      if (s == null || s.isEmpty) return null;
      final root = jsonDecode(s);
      if (root is! Map) return null;
      final block = root['$conversationId'];
      if (block is! Map) return null;
      final j = Map<String, dynamic>.from(block);
      final conv = Conversation.fromJson(Map<String, dynamic>.from(asMap(j['conversation'])));
      final rawList = j['messages'] is List ? (j['messages'] as List) : const <dynamic>[];
      final msgs = <Message>[];
      final rawMaps = <Map<String, dynamic>>[];
      for (final e in rawList) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        rawMaps.add(m);
        msgs.add(Message.fromJson(m));
      }
      if (msgs.isEmpty) return null;
      final older = j['older'] is Map ? Map<String, dynamic>.from(asMap(j['older'])) : null;
      final entry = ChatCacheEntry(
        conversation: conv,
        messages: msgs,
        older: older,
        since: asStr(j['since']),
        seenId: asInt(j['seen_id'], conv.partnerLastReadId),
        loadedAt: DateTime.now(),
        rawConversation: Map<String, dynamic>.from(asMap(j['conversation'])),
        rawMessages: rawMaps,
      );
      _store[conversationId] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistDisk(int conversationId, Map<String, dynamic> block) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> root = {};
      final prev = prefs.getString(_diskKey);
      if (prev != null && prev.isNotEmpty) {
        final decoded = jsonDecode(prev);
        if (decoded is Map) root = Map<String, dynamic>.from(decoded.map((k, v) => MapEntry('$k', v)));
      }
      root['$conversationId'] = block;
      while (root.length > _maxDiskChats) {
        DateTime? oldest;
        String? drop;
        for (final e in root.entries) {
          final at = asStr(asMap(e.value)['saved_at']);
          final t = DateTime.tryParse(at);
          if (t == null) continue;
          if (oldest == null || t.isBefore(oldest)) {
            oldest = t;
            drop = e.key;
          }
        }
        if (drop == null) break;
        root.remove(drop);
      }
      await prefs.setString(_diskKey, jsonEncode(root));
    } catch (_) {}
  }

  static void patchConversation(int id, Conversation conversation) {
    final e = _store[id];
    if (e == null) return;
    e.conversation = conversation;
    e.loadedAt = DateTime.now();
  }
}

class ChatCacheEntry {
  ChatCacheEntry({
    required this.conversation,
    required this.messages,
    required this.older,
    required this.since,
    required this.seenId,
    required this.loadedAt,
    this.rawConversation,
    this.rawMessages,
  });

  Conversation conversation;
  final List<Message> messages;
  Map<String, dynamic>? older;
  String since;
  int seenId;
  DateTime loadedAt;
  final Map<String, dynamic>? rawConversation;
  final List<Map<String, dynamic>>? rawMessages;
}