import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';
import 'group_info_screen.dart';

String mimeOf(String name) {
  final e = name.split('.').last.toLowerCase();
  return const {
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
        'pdf': 'application/pdf', 'doc': 'application/msword', 'xls': 'application/vnd.ms-excel',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'm4a': 'audio/mp4', 'mp3': 'audio/mpeg', 'mp4': 'video/mp4', 'txt': 'text/plain', 'zip': 'application/zip',
      }[e] ??
      'application/octet-stream';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatStore _s = context.read<ChatStore>();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Msg? _reply;
  bool _loading = true, _more = true, _loadingOlder = false;
  // voice recording
  final _rec = AudioRecorder();
  bool _recording = false;
  final _sw = Stopwatch();
  Timer? _recTimer;

  @override
  void initState() {
    super.initState();
    _s.open(widget.chatId);
    _s.loadMessages(widget.chatId).catchError((e) { if (mounted) toast(context, '$e'); }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
      _s.markRead(widget.chatId);
    });
    _scroll.addListener(() async {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200 && _more && !_loadingOlder && !_loading) {
        _loadingOlder = true;
        try { _more = await _s.loadOlder(widget.chatId); } catch (_) {}
        _loadingOlder = false;
      }
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _s.close(widget.chatId);
    _recTimer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _s.sendText(widget.chatId, t, replyTo: _reply?.id);
    _text.clear();
    setState(() => _reply = null);
  }

  Future<void> _sendFile(String path, String name, String kind, {int dur = 0}) async {
    final reply = _reply?.id;
    setState(() => _reply = null);
    try {
      await _s.sendFile(widget.chatId, File(path), name, mimeOf(name), kind, dur: dur, replyTo: reply);
    } catch (e) {
      if (mounted) toast(context, 'Could not send: $e');
    }
  }

  Future<void> _attach() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _attachBtn(ctx, 'camera', Icons.photo_camera, 'Camera', const Color(0xFFD81B60)),
            _attachBtn(ctx, 'gallery', Icons.photo, 'Photo', const Color(0xFF8E24AA)),
            _attachBtn(ctx, 'doc', Icons.insert_drive_file, 'Document', const Color(0xFF3949AB)),
          ]),
        ),
      ),
    );
    if (v == null) return;
    if (v == 'doc') {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true);
      for (final f in r?.files ?? <PlatformFile>[]) {
        if (f.path == null) continue;
        final isImg = mimeOf(f.name).startsWith('image/');
        await _sendFile(f.path!, f.name, isImg ? 'image' : 'file');
      }
    } else if (v == 'gallery') {
      final list = await ImagePicker().pickMultiImage(imageQuality: 82, maxWidth: 2200);
      for (final x in list) { await _sendFile(x.path, x.name, 'image'); }
    } else {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 2200);
      if (x != null) await _sendFile(x.path, x.name, 'image');
    }
  }

  Widget _attachBtn(BuildContext ctx, String v, IconData i, String t, Color c) => InkWell(
        onTap: () => Navigator.pop(ctx, v),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 28, backgroundColor: c, child: Icon(i, color: Colors.white, size: 26)),
          const SizedBox(height: 6),
          Text(t),
        ]),
      );

  // ───────── voice
  Future<void> _startRec() async {
    try {
      if (!await _rec.hasPermission()) { if (mounted) toast(context, 'Microphone permission is needed'); return; }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
      HapticFeedback.mediumImpact();
      _sw..reset()..start();
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) { if (mounted) setState(() {}); });
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) toast(context, 'Recording failed: $e');
    }
  }

  Future<void> _stopRec({required bool send}) async {
    _recTimer?.cancel();
    _sw.stop();
    final dur = _sw.elapsedMilliseconds;
    setState(() => _recording = false);
    try {
      if (!send) { await _rec.cancel(); return; }
      final path = await _rec.stop();
      if (path == null || dur < 700) return;
      await _sendFile(path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a', 'voice', dur: dur);
    } catch (e) {
      if (mounted) toast(context, 'Recording failed: $e');
    }
  }

  // ───────── message actions
  Future<void> _msgMenu(Chat c, Msg m) async {
    if (m.deleted) return;
    final mine = m.from == _s.me;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.kind == 'text') ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () => Navigator.pop(ctx, 'copy')),
          if (mine && !m.pending) ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFB42318)),
              title: const Text('Delete for everyone'), onTap: () => Navigator.pop(ctx, 'delete')),
          if (mine && !m.pending && c.isGroup) ListTile(leading: const Icon(Icons.info_outline), title: const Text('Read by'),
              onTap: () => Navigator.pop(ctx, 'info')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (v) {
      case 'reply': setState(() => _reply = m);
      case 'copy': Clipboard.setData(ClipboardData(text: m.text)); toast(context, 'Copied');
      case 'delete': _s.deleteMsg(m);
      case 'info':
        final read = c.members.where((u) => u != _s.me && (c.state[u]?.read ?? 0) >= m.seq).map((u) => _s.user(u)?.name ?? '').toList();
        final del = c.members.where((u) => u != _s.me && !read.contains(_s.user(u)?.name) && (c.state[u]?.delivered ?? 0) >= m.seq)
            .map((u) => _s.user(u)?.name ?? '').toList();
        showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Message info'),
          content: Text('Read by: ${read.isEmpty ? '—' : read.join(', ')}\n\nDelivered to: ${del.isEmpty ? '—' : del.join(', ')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    final c = s.chat(widget.chatId);
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Chat not found')));
    final list = s.msgs[c.id] ?? const <Msg>[];
    final other = s.otherUser(c);
    final typing = s.typingText(c);
    final sub = typing ??
        (c.isGroup
            ? c.members.map((u) => u == s.me ? 'You' : (s.user(u)?.name.split(' ').first ?? '')).join(', ')
            : (other == null ? '' : (other.online ? 'online' : lastSeenText(other.lastSeen))));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            if (c.isGroup) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(chatId: c.id)));
            } else if (other != null) {
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: Text(other.name),
                content: Text('+${other.phone}\n\n${other.about}'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
              ));
            }
          },
          child: Row(children: [
            Avatar(c.isGroup ? '' : (other?.initials ?? '?'), size: 38, group: c.isGroup, seed: c.id),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: typing != null ? gold : const Color(0xFFC8D1E6))),
              ]),
            ),
          ]),
        ),
      ),
      backgroundColor: chatBg,
      body: Column(children: [
        Expanded(
          child: _loading && list.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final idx = list.length - 1 - i;
                    final m = list[idx];
                    final prev = idx > 0 ? list[idx - 1] : null;
                    final newDay = prev == null || dayLabel(prev.ts) != dayLabel(m.ts);
                    final sameSender = prev != null && !newDay && prev.from == m.from;
                    Msg? quoted;
                    if (m.replyTo != null) {
                      for (final x in list) { if (x.id == m.replyTo) { quoted = x; break; } }
                    }
                    return Column(children: [
                      if (newDay) _dayChip(dayLabel(m.ts)),
                      GestureDetector(
                        onLongPress: () => _msgMenu(c, m),
                        onHorizontalDragEnd: (d) { if ((d.primaryVelocity ?? 0) > 300 && !m.deleted) setState(() => _reply = m); },
                        child: Bubble(store: s, chat: c, msg: m, quoted: quoted, showName: c.isGroup && !sameSender && m.from != s.me),
                      ),
                    ]);
                  },
                ),
        ),
        _inputBar(s, c),
      ]),
    );
  }

  Widget _dayChip(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFDDE3EE), borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: const TextStyle(fontSize: 12, color: muted)),
        ),
      );

  Widget _inputBar(ChatStore s, Chat c) {
    if (_recording) {
      return SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            IconButton(tooltip: 'Cancel', icon: const Icon(Icons.delete_outline, color: Color(0xFFB42318)), onPressed: () => _stopRec(send: false)),
            const Icon(Icons.fiber_manual_record, color: Color(0xFFE53935), size: 16),
            const SizedBox(width: 6),
            Text(durLabel(_sw.elapsedMilliseconds), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Recording…', style: TextStyle(color: muted))),
            FloatingActionButton.small(heroTag: null, tooltip: 'Send voice', onPressed: () => _stopRec(send: true), child: const Icon(Icons.send)),
          ]),
        ),
      );
    }
    final hasText = _text.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        color: chatBg,
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_reply != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  border: const Border(left: BorderSide(color: waGreen, width: 4))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_reply!.from == s.me ? 'You' : (s.user(_reply!.from)?.name ?? ''),
                        style: const TextStyle(color: waGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(_reply!.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
                  ]),
                ),
                IconButton(tooltip: 'Cancel reply', icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _reply = null)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  IconButton(tooltip: 'Attach', icon: const Icon(Icons.attach_file, color: muted), onPressed: _attach),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1, maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Message', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                      onChanged: (_) => s.typingNow(c.id),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Camera', icon: const Icon(Icons.photo_camera, color: muted),
                    onPressed: () async {
                      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 2200);
                      if (x != null) await _sendFile(x.path, x.name, 'image');
                    },
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 50, height: 50,
              child: FloatingActionButton(
                heroTag: null,
                elevation: 1,
                tooltip: hasText ? 'Send' : 'Record voice',
                onPressed: hasText ? _sendText : _startRec,
                child: Icon(hasText ? Icons.send : Icons.mic),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// One message bubble.
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.store, required this.chat, required this.msg, this.quoted, this.showName = false});
  final ChatStore store;
  final Chat chat;
  final Msg msg;
  final Msg? quoted;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final mine = msg.from == store.me;
    final sender = store.user(msg.from);
    final w = MediaQuery.of(context).size.width * .78;
    Widget body;
    if (msg.deleted) {
      body = const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 16, color: muted), SizedBox(width: 6),
        Text('This message was deleted', style: TextStyle(fontStyle: FontStyle.italic, color: muted)),
      ]);
    } else {
      switch (msg.kind) {
        case 'image': body = _image(context);
        case 'file': body = _file(context);
        case 'voice': body = VoicePlayer(msg: msg);
        default: body = Text(msg.text, style: const TextStyle(fontSize: 15.5, height: 1.3));
      }
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: w),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
        decoration: BoxDecoration(
          color: mine ? bubbleMine : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 3), bottomRight: Radius.circular(mine ? 3 : 14)),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(sender?.name ?? '', style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          if (quoted != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(color: Colors.black.withAlpha(13), borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: waGreen, width: 3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(quoted!.from == store.me ? 'You' : (store.user(quoted!.from)?.name ?? ''),
                    style: const TextStyle(color: waGreen, fontWeight: FontWeight.w700, fontSize: 12)),
                Text(quoted!.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: muted)),
              ]),
            ),
          body,
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (msg.failed) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.error_outline, size: 14, color: Color(0xFFB42318))),
            Text(hhmm(msg.ts), style: const TextStyle(fontSize: 11, color: muted)),
            if (mine && !msg.deleted) Padding(padding: const EdgeInsets.only(left: 3), child: tickIcon(store.ticks(chat, msg), size: 15)),
          ]),
        ]),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final f = msg.file;
    final Widget img = msg.localPath != null && File(msg.localPath!).existsSync()
        ? Image.file(File(msg.localPath!), fit: BoxFit.cover)
        : (f == null || f.id.isEmpty)
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : Image.network(Api.fileUrl(f.id), fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image, size: 40, color: muted))));
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewScreen(child: img))),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: img)),
    );
  }

  Widget _file(BuildContext context) {
    final f = msg.file;
    final pdf = (f?.name ?? '').toLowerCase().endsWith('.pdf');
    return InkWell(
      onTap: () async {
        try {
          final path = msg.localPath ?? await Api.download(f!.id, f.name);
          await OpenFilex.open(path);
        } catch (e) {
          if (context.mounted) toast(context, '$e');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withAlpha(10), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38, height: 46,
            decoration: BoxDecoration(color: pdf ? const Color(0xFFE5484D) : const Color(0xFF3949AB), borderRadius: BorderRadius.circular(5)),
            alignment: Alignment.center,
            child: Text(pdf ? 'PDF' : (f?.name.split('.').last.toUpperCase() ?? 'FILE'),
                maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f?.name ?? 'File', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(msg.pending ? 'Sending…' : (f?.sizeLabel ?? ''), style: const TextStyle(fontSize: 12, color: muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Play / pause a voice message with a seek bar.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.msg});
  final Msg msg;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _p = AudioPlayer();
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: widget.msg.file?.dur ?? 0);
    _subs.add(_p.onPositionChanged.listen((d) { if (mounted) setState(() => _pos = d); }));
    _subs.add(_p.onDurationChanged.listen((d) { if (mounted && d > Duration.zero) setState(() => _dur = d); }));
    _subs.add(_p.onPlayerComplete.listen((_) { if (mounted) setState(() { _playing = false; _pos = Duration.zero; }); }));
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _p.pause();
        setState(() => _playing = false);
        return;
      }
      setState(() => _playing = true);
      if (_pos > Duration.zero) {
        await _p.resume();
      } else {
        final m = widget.msg;
        final Source src = m.localPath != null && File(m.localPath!).existsSync()
            ? DeviceFileSource(m.localPath!)
            : UrlSource(Api.fileUrl(m.file!.id));
        await _p.play(src);
      }
    } catch (e) {
      if (mounted) { setState(() => _playing = false); toast(context, 'Cannot play: $e'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _dur.inMilliseconds > 0 ? _dur.inMilliseconds : 1;
    return SizedBox(
      width: 230,
      child: Row(children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 38, color: waGreen),
          onPressed: widget.msg.pending && widget.msg.localPath == null ? null : _toggle,
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
              child: Slider(
                value: (_pos.inMilliseconds / total).clamp(0.0, 1.0),
                activeColor: waGreen,
                onChanged: (v) => _p.seek(Duration(milliseconds: (v * total).round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(durLabel((_playing || _pos > Duration.zero) ? _pos.inMilliseconds : _dur.inMilliseconds),
                  style: const TextStyle(fontSize: 11, color: muted)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class ImageViewScreen extends StatelessWidget {
  const ImageViewScreen({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(child: InteractiveViewer(maxScale: 6, child: child)),
      );
}
