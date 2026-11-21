import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../store.dart';
import '../ui.dart';
import 'chat_screen.dart';
import 'new_group_screen.dart';

/// Pick a staff member to chat with.
class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    final staff = s.users.values.where((u) => u.id != s.me).toList()..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text('Select staff (${staff.length})')),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(radius: 23, backgroundColor: waGreen, child: Icon(Icons.group_add, color: Colors.white)),
          title: const Text('New group', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NewGroupScreen())),
        ),
        const Divider(height: 1),
        for (final u in staff)
          ListTile(
            leading: Avatar(u.initials, online: u.online, seed: u.id),
            title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(u.about.isNotEmpty ? u.about : (u.online ? 'online' : lastSeenText(u.lastSeen))),
            trailing: u.role == 'admin' ? const Text('Admin', style: TextStyle(color: muted, fontSize: 12)) : null,
            onTap: () async {
              try {
                final c = await s.direct(u.id);
                if (context.mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
                }
              } catch (e) {
                if (context.mounted) toast(context, '$e');
              }
            },
          ),
      ]),
    );
  }
}
