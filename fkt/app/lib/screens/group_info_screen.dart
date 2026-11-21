import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';
import 'new_group_screen.dart';

class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    final c = s.chat(chatId);
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('You are not in this group')));
    final amAdmin = c.admins.contains(s.me) || Session.me?['role'] == 'admin';
    final members = c.members.map((u) => s.user(u)).whereType<Object>().toList();
    Future<void> act(Future<void> Function() f) async {
      try { await f(); } catch (e) { if (context.mounted) toast(context, '$e'); }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: ListView(children: [
        const SizedBox(height: 20),
        Center(child: Avatar('', size: 90, group: true, seed: c.id)),
        const SizedBox(height: 10),
        Center(child: Text(c.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        Center(child: Text('Group · ${c.members.length} members', style: const TextStyle(color: muted))),
        if (amAdmin)
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.edit), label: const Text('Rename'),
              onPressed: () async {
                final ctl = TextEditingController(text: c.name);
                final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Group name'),
                  content: TextField(controller: ctl, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
                  ],
                ));
                if (n != null && n.isNotEmpty) await act(() => s.updateGroup(c.id, {'name': n}));
              },
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('${members.length} members', style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
        ),
        if (amAdmin)
          ListTile(
            leading: const CircleAvatar(backgroundColor: waGreen, child: Icon(Icons.person_add, color: Colors.white)),
            title: const Text('Add members'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewGroupScreen(chatId: c.id))),
          ),
        for (final uid in c.members)
          Builder(builder: (_) {
            final u = s.user(uid);
            final isAdmin = c.admins.contains(uid);
            return ListTile(
              leading: Avatar(u?.initials ?? '?', online: u?.online ?? false, seed: uid),
              title: Text(uid == s.me ? 'You' : (u?.name ?? 'Staff')),
              subtitle: Text(u == null ? '' : (u.online ? 'online' : lastSeenText(u.lastSeen))),
              trailing: isAdmin
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE9F9EF), borderRadius: BorderRadius.circular(6)),
                      child: const Text('Group admin', style: TextStyle(color: waGreen, fontSize: 12)))
                  : null,
              onLongPress: !amAdmin || uid == s.me
                  ? null
                  : () async {
                      final v = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          if (!isAdmin) ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Make group admin'),
                              onTap: () => Navigator.pop(ctx, 'admin')),
                          ListTile(leading: const Icon(Icons.person_remove, color: Color(0xFFB42318)), title: Text('Remove ${u?.name ?? ''}'),
                              onTap: () => Navigator.pop(ctx, 'remove')),
                        ]),
                      ));
                      if (v == 'admin') await act(() => s.updateGroup(c.id, {'makeAdmin': [uid]}));
                      if (v == 'remove') await act(() => s.updateGroup(c.id, {'remove': [uid]}));
                    },
            );
          }),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFFB42318)),
          title: const Text('Leave group', style: TextStyle(color: Color(0xFFB42318))),
          onTap: () async {
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: Text('Leave "${c.name}"?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
              ],
            ));
            if (ok != true) return;
            await act(() => s.updateGroup(c.id, {'leave': true}));
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
