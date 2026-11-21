import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';
import 'models.dart';
import 'session.dart';

/// All chat state + the live connection to the server.
class ChatStore extends ChangeNotifier {
  final Map<String, AppUser> users = {};
  final List<Chat> chats = [];
  final Map<String, List<Msg>> msgs = {};
  final Map<String, Map<String, int>> typing = {}; // chatId -> userId -> time
  final _incoming = StreamController<Msg>.broadcast();
  Stream<Msg> get incoming => _incoming.stream;

  String? openChatId;
  bool connected = false, started = false;
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry, _ping, _typingTimer;
  final List<Map<String, dynamic>> _outbox = [];

  String get me => Session.myId;
  AppUser? user(String id) => users[id];
  Chat? chat(String id) {
    for (final c in chats) { if (c.id == id) return c; }
    return null;
  }

  String title(Chat c) {
    if (c.isGroup) return c.name;
    final other = c.members.firstWhere((m) => m != me, orElse: () => me);
    return users[other]?.name ?? 'Staff';
  }

  AppUser? otherUser(Chat c) {
    if (c.isGroup) return null;
    return users[c.members.firstWhere((m) => m != me, orElse: () => me)];
  }

  // ───────── start / stop
  Future<void> start() async {
    if (started) return;
    started = true;
    await refresh();
    _connect();
    _typingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final cut = DateTime.now().millisecondsSinceEpoch - 4000;
      var changed = false;
      for (final m in typing.values) {
        final n = m.length;
        m.removeWhere((_, t) => t < cut);
        if (m.length != n) changed = true;
      }
      if (changed) notifyListeners();
    });
  }

  Future<void> refresh() async {
    try {
      final u = await Api.get('/api/users');
      for (final j in u['users'] as List) {
        final x = AppUser.fromJson(j as Map<String, dynamic>);
        users[x.id] = x;
      }
      final c = await Api.get('/api/chats');
      chats
        ..clear()
        ..addAll([for (final j in c['chats'] as List) Chat.fromJson(j as Map<String, dynamic>)]);
      _sort();
      notifyListeners();
    } catch (_) {}
  }

  void stop() {
    started = false;
    _retry?.cancel();
    _ping?.cancel();
    _typingTimer?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
    connected = false;
    users.clear();
    chats.clear();
    msgs.clear();
  }

  void _connect() {
    if (!started || Session.token == null) return;
    _retry?.cancel();
    try {
      final ch = WebSocketChannel.connect(Uri.parse(Api.wsUrl));
      _ch = ch;
      ch.ready.then((_) {
        connected = true;
        notifyListeners();
        refresh();
        for (final o in List.of(_outbox)) { ch.sink.add(jsonEncode(o)); }
        _outbox.clear();
      }).catchError((_) => _lost());
      _sub = ch.stream.listen((d) => _event(d as String), onDone: _lost, onError: (_) => _lost());
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'t': 'ping'}));
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    if (connected) { connected = false; notifyListeners(); }
    _ch = null;
    _retry?.cancel();
    if (started) _retry = Timer(const Duration(seconds: 3), _connect);
  }

  /// Call when the app comes back to the screen.
  void resume() { if (started && !connected) _connect(); }

  void _send(Map<String, dynamic> o, {bool queue = false}) {
    if (connected && _ch != null) {
      _ch!.sink.add(jsonEncode(o));
    } else if (queue) {
      _outbox.add(o);
    }
  }

  void _sort() => chats.sort((a, b) => b.sortTime.compareTo(a.sortTime));

  // ───────── events from the server
  void _event(String raw) {
    Map<String, dynamic> o;
    try { o = jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return; }
    switch (o['t']) {
      case 'msg':
        final m = Msg.fromJson(o['msg'] as Map<String, dynamic>);
        _addMsg(m);
        final c = chat(m.chatId);
        if (c != null) {
          c.last = m;
          if (m.seq > c.lastSeq) c.lastSeq = m.seq;
          if (m.from != me) {
            if (openChatId == m.chatId) {
              _send({'t': 'read', 'chatId': m.chatId, 'upTo': m.seq});
            } else {
              c.unread++;
              _incoming.add(m);
            }
          }
          _sort();
        } else {
          refresh();
        }
        typing[m.chatId]?.remove(m.from);
      case 'ack':
        final m = Msg.fromJson(o['msg'] as Map<String, dynamic>);
        final list = msgs[m.chatId];
        if (list != null) {
          final i = list.indexWhere((x) => x.tempId == o['tempId'] || x.id == m.id);
          if (i >= 0) {
            m.localPath = list[i].localPath;
            list[i] = m;
          } else {
            list.add(m);
          }
        }
      case 'state':
        final c = chat(o['chatId'] as String);
        if (c != null) {
          c.state[o['userId'] as String] =
              ChatState((o['read'] as num?)?.toInt() ?? 0, (o['delivered'] as num?)?.toInt() ?? 0);
        }
      case 'typing':
        (typing[o['chatId'] as String] ??= {})[o['userId'] as String] = DateTime.now().millisecondsSinceEpoch;
      case 'presence':
        final u = users[o['userId']];
        if (u != null) {
          u.online = o['online'] == true;
          u.lastSeen = (o['lastSeen'] as num?)?.toInt() ?? u.lastSeen;
        }
      case 'user':
        final u = AppUser.fromJson(o['user'] as Map<String, dynamic>);
        users[u.id] = u;
        if (u.id == me) Session.setMe(o['user'] as Map<String, dynamic>);
      case 'chat':
        final c = Chat.fromJson(o['chat'] as Map<String, dynamic>);
        final i = chats.indexWhere((x) => x.id == c.id);
        if (i >= 0) {
          c.last ??= chats[i].last;
          chats[i] = c;
        } else {
          chats.add(c);
        }
        _sort();
      case 'left':
        chats.removeWhere((x) => x.id == o['chatId']);
      case 'deleted':
        for (final m in msgs[o['chatId']] ?? const <Msg>[]) {
          if (m.id == o['msgId']) { m.deleted = true; m.text = ''; m.file = null; }
        }
        final c = chat(o['chatId'] as String);
        if (c?.last?.id == o['msgId']) c!.last!.deleted = true;
      default:
        return;
    }
    notifyListeners();
  }

  void _addMsg(Msg m) {
    final list = msgs[m.chatId];
    if (list == null) return;
    if (list.any((x) => x.id == m.id)) return;
    // my own message comes back as 'msg' too: replace the pending copy
    if (m.from == me) {
      final i = list.indexWhere((x) => x.pending && x.kind == m.kind && (x.text == m.text) && x.tempId != null);
      if (i >= 0) { m.localPath = list[i].localPath; list[i] = m; return; }
    }
    list.add(m);
  }

  // ───────── actions
  Future<void> loadMessages(String chatId) async {
    final r = await Api.get('/api/chats/$chatId/messages?limit=80');
    msgs[chatId] = [for (final j in r['messages'] as List) Msg.fromJson(j as Map<String, dynamic>)];
    notifyListeners();
  }

  Future<bool> loadOlder(String chatId) async {
    final list = msgs[chatId];
    if (list == null || list.isEmpty) return false;
    final r = await Api.get('/api/chats/$chatId/messages?limit=80&before=${list.first.seq}');
    final older = [for (final j in r['messages'] as List) Msg.fromJson(j as Map<String, dynamic>)];
    list.insertAll(0, older);
    notifyListeners();
    return r['more'] == true;
  }

  void open(String chatId) {
    openChatId = chatId;
    markRead(chatId);
  }

  void close(String chatId) { if (openChatId == chatId) openChatId = null; }

  void markRead(String chatId) {
    final c = chat(chatId);
    if (c == null) return;
    c.unread = 0;
    if (c.lastSeq > 0) _send({'t': 'read', 'chatId': chatId, 'upTo': c.lastSeq});
    notifyListeners();
  }

  int _lastTyping = 0;
  void typingNow(String chatId) {
    final t = DateTime.now().millisecondsSinceEpoch;
    if (t - _lastTyping < 3000) return;
    _lastTyping = t;
    _send({'t': 'typing', 'chatId': chatId});
  }

  String _tempId() => 't${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}';

  Msg _pending(String chatId, String kind, {String text = '', String? replyTo, String? localPath, FileRef? file}) {
    final m = Msg(id: _tempId(), seq: 1 << 30, chatId: chatId, from: me, kind: kind, text: text, replyTo: replyTo,
        ts: DateTime.now().millisecondsSinceEpoch, pending: true, localPath: localPath, file: file)
      ..tempId = null;
    m.tempId = m.id;
    (msgs[chatId] ??= []).add(m);
    notifyListeners();
    return m;
  }

  void sendText(String chatId, String text, {String? replyTo}) {
    final m = _pending(chatId, 'text', text: text, replyTo: replyTo);
    _send({'t': 'send', 'chatId': chatId, 'tempId': m.tempId, 'kind': 'text', 'text': text, 'replyTo': replyTo}, queue: true);
  }

  Future<void> sendFile(String chatId, File f, String name, String mime, String kind, {int dur = 0, String? replyTo}) async {
    final m = _pending(chatId, kind, localPath: f.path, replyTo: replyTo,
        file: FileRef('', name, mime, f.lengthSync(), dur));
    try {
      final up = await Api.upload(f, name, mime);
      _send({
        't': 'send', 'chatId': chatId, 'tempId': m.tempId, 'kind': kind, 'text': '',
        'file': {'id': up['id'], 'dur': dur}, 'replyTo': replyTo,
      }, queue: true);
    } catch (e) {
      m.failed = true;
      notifyListeners();
      rethrow;
    }
  }

  void deleteMsg(Msg m) => _send({'t': 'delete', 'chatId': m.chatId, 'msgId': m.id});

  Future<Chat> direct(String userId) async {
    final r = await Api.post('/api/chats/direct', {'userId': userId});
    return _upsert(r['chat'] as Map<String, dynamic>);
  }

  Future<Chat> createGroup(String name, List<String> members) async {
    final r = await Api.post('/api/chats/group', {'name': name, 'members': members});
    return _upsert(r['chat'] as Map<String, dynamic>);
  }

  Future<Chat> updateGroup(String chatId, Map<String, dynamic> body) async {
    final r = await Api.post('/api/chats/$chatId', body);
    if (body['leave'] == true) {
      chats.removeWhere((x) => x.id == chatId);
      notifyListeners();
    }
    return _upsert(r['chat'] as Map<String, dynamic>, add: body['leave'] != true);
  }

  Chat _upsert(Map<String, dynamic> j, {bool add = true}) {
    final c = Chat.fromJson(j);
    final i = chats.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      c.last ??= chats[i].last;
      chats[i] = c;
    } else if (add) {
      chats.add(c);
    }
    _sort();
    notifyListeners();
    return c;
  }

  /// ✓ sent, ✓✓ delivered, blue ✓✓ read (by everyone else in the chat).
  int ticks(Chat c, Msg m) {
    if (m.pending) return 0;
    final others = c.members.where((x) => x != me).toList();
    if (others.isEmpty) return 3;
    if (others.every((o) => (c.state[o]?.read ?? 0) >= m.seq)) return 3;
    if (others.every((o) => (c.state[o]?.delivered ?? 0) >= m.seq)) return 2;
    return 1;
  }

  String? typingText(Chat c) {
    final t = typing[c.id];
    if (t == null || t.isEmpty) return null;
    if (!c.isGroup) return 'typing…';
    final names = t.keys.map((u) => users[u]?.name.split(' ').first ?? '').where((s) => s.isNotEmpty).toList();
    return names.isEmpty ? 'typing…' : '${names.join(', ')} typing…';
  }
}
