import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';
import '../session.dart';
import 'admin_screen.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'new_group_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _search = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ChatStore>().start());
  }

  void _open(Chat c) => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    var list = s.chats;
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list.where((c) => s.title(c).toLowerCase().contains(q)).toList();
    }
    return Scaffold(
      appBar: AppBar(
        title: _search
            ? TextField(
                autofocus: true, style: const TextStyle(color: Colors.white), cursorColor: Colors.white,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Search…', hintStyle: TextStyle(color: Colors.white60)),
                onChanged: (v) => setState(() => _q = v),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Kepler Messenger', style: TextStyle(fontWeight: FontWeight.w700)),
                if (!s.connected) const Text('Connecting…', style: TextStyle(fontSize: 12, color: Color(0xFFC8D1E6))),
              ]),
        actions: [
          IconButton(
            icon: Icon(_search ? Icons.close : Icons.search),
            tooltip: 'Search',
            onPressed: () => setState(() { _search = !_search; _q = ''; }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'group') Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGroupScreen()));
              if (v == 'profile') Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              if (v == 'admin') Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'group', child: Text('New group')),
              if (Session.isAdmin) const PopupMenuItem(value: 'admin', child: Text('Admin (approve staff, SMS)')),
              const PopupMenuItem(value: 'profile', child: Text('Profile & settings')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 140),
                Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFFB8C0CF)),
                SizedBox(height: 12),
                Text('No chats yet.\nTap the green button to message your staff.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ])
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                itemBuilder: (_, i) => _tile(s, list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New chat',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen())),
        child: const Icon(Icons.chat),
      ),
    );
  }

  Widget _tile(ChatStore s, Chat c) {
    final other = s.otherUser(c);
    final typing = s.typingText(c);
    final last = c.last;
    final mine = last != null && last.from == s.me;
    final sender = c.isGroup && last != null && !mine ? '${s.user(last.from)?.name.split(' ').first ?? ''}: ' : '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Avatar(c.isGroup ? '' : (other?.initials ?? '?'), group: c.isGroup, online: other?.online ?? false, seed: c.id),
      title: Text(s.title(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: typing != null
          ? Text(typing, style: const TextStyle(color: waGreen, fontWeight: FontWeight.w600))
          : Row(children: [
              if (mine) Padding(padding: const EdgeInsets.only(right: 4), child: tickIcon(s.ticks(c, last))),
              Expanded(
                child: Text(last == null ? (c.isGroup ? 'Group created' : 'Say salam 👋') : '$sender${last.preview}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(listTime(c.sortTime), style: TextStyle(fontSize: 12, color: c.unread > 0 ? waGreen : muted)),
        const SizedBox(height: 4),
        if (c.unread > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: waGreen, borderRadius: BorderRadius.circular(12)),
            child: Text('${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          )
        else
          const SizedBox(height: 18),
      ]),
      onTap: () => _open(c),
    );
  }
}
