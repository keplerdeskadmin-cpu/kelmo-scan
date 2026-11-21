class AppUser {
  AppUser(this.id, this.name, this.phone, this.about, this.role, this.online, this.lastSeen);
  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        j['id'] as String, (j['name'] as String?) ?? '', (j['phone'] as String?) ?? '', (j['about'] as String?) ?? '',
        (j['role'] as String?) ?? 'staff', j['online'] == true, (j['lastSeen'] as num?)?.toInt() ?? 0);
  final String id;
  String name, phone, about, role;
  bool online;
  int lastSeen;

  String get initials {
    final p = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }
}

class FileRef {
  FileRef(this.id, this.name, this.mime, this.size, this.dur);
  factory FileRef.fromJson(Map<String, dynamic> j) => FileRef(j['id'] as String, (j['name'] as String?) ?? 'file',
      (j['mime'] as String?) ?? '', (j['size'] as num?)?.toInt() ?? 0, (j['dur'] as num?)?.toInt() ?? 0);
  final String id, name, mime;
  final int size, dur; // dur = voice length in ms

  String get sizeLabel {
    if (size >= 1 << 20) return '${(size / (1 << 20)).toStringAsFixed(1)} MB';
    if (size >= 1024) return '${(size / 1024).round()} KB';
    return '$size B';
  }
}

class Msg {
  Msg({required this.id, required this.seq, required this.chatId, required this.from, required this.kind,
      this.text = '', this.file, this.replyTo, required this.ts, this.deleted = false, this.tempId, this.pending = false,
      this.failed = false, this.localPath});

  factory Msg.fromJson(Map<String, dynamic> j) => Msg(
        id: j['id'] as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        chatId: j['chatId'] as String,
        from: j['from'] as String,
        kind: (j['kind'] as String?) ?? 'text',
        text: (j['text'] as String?) ?? '',
        file: j['file'] == null ? null : FileRef.fromJson(j['file'] as Map<String, dynamic>),
        replyTo: j['replyTo'] as String?,
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        deleted: j['deleted'] == true,
      );

  String id;
  int seq;
  final String chatId, from, kind;
  String text;
  FileRef? file;
  final String? replyTo;
  int ts;
  bool deleted, pending, failed;
  String? tempId, localPath;

  String get preview {
    if (deleted) return 'This message was deleted';
    switch (kind) {
      case 'image': return '📷 Photo';
      case 'voice': return '🎤 Voice message';
      case 'file': return '📄 ${file?.name ?? 'File'}';
      default: return text;
    }
  }
}

class ChatState {
  ChatState(this.read, this.delivered);
  int read, delivered;
}

class Chat {
  Chat({required this.id, required this.type, required this.name, required this.members, required this.admins,
      required this.created, required this.lastSeq, required this.state, this.last, this.unread = 0});

  factory Chat.fromJson(Map<String, dynamic> j) {
    final st = <String, ChatState>{};
    (j['state'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final m = v as Map<String, dynamic>;
      st[k] = ChatState((m['read'] as num?)?.toInt() ?? 0, (m['delivered'] as num?)?.toInt() ?? 0);
    });
    return Chat(
      id: j['id'] as String,
      type: (j['type'] as String?) ?? 'direct',
      name: (j['name'] as String?) ?? '',
      members: [for (final x in (j['members'] as List? ?? const [])) x as String],
      admins: [for (final x in (j['admins'] as List? ?? const [])) x as String],
      created: (j['created'] as num?)?.toInt() ?? 0,
      lastSeq: (j['lastSeq'] as num?)?.toInt() ?? 0,
      state: st,
      last: j['last'] == null ? null : Msg.fromJson(j['last'] as Map<String, dynamic>),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
    );
  }

  final String id, type;
  String name;
  List<String> members, admins;
  final int created;
  int lastSeq, unread;
  Map<String, ChatState> state;
  Msg? last;

  bool get isGroup => type == 'group';
  int get sortTime => last?.ts ?? created;
}
