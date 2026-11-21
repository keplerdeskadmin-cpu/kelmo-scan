import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../store.dart';
import '../ui.dart';
import 'chat_screen.dart';

/// Create a group, or add members to an existing one ([chatId]).
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, this.chatId});
  final String? chatId;
  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final Set<String> _sel = {};
  bool _busy = false;

  Future<void> _save() async {
    final s = context.read<ChatStore>();
    if (_sel.isEmpty) { toast(context, 'Select at least one person'); return; }
    if (widget.chatId == null && _name.text.trim().isEmpty) { toast(context, 'Type a group name'); return; }
    setState(() => _busy = true);
    try {
      if (widget.chatId != null) {
        await s.updateGroup(widget.chatId!, {'add': _sel.toList()});
        if (mounted) Navigator.pop(context);
      } else {
        final c = await s.createGroup(_name.text.trim(), _sel.toList());
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    final existing = widget.chatId == null ? <String>[] : (s.chat(widget.chatId!)?.members ?? <String>[]);
    final staff = s.users.values.where((u) => u.id != s.me && !existing.contains(u.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text(widget.chatId == null ? 'New group' : 'Add members')),
      body: Column(children: [
        if (widget.chatId == null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Ticketing, Visa, Accounts', prefixIcon: Icon(Icons.groups))),
          ),
        Expanded(
          child: ListView(children: [
            for (final u in staff)
              CheckboxListTile(
                value: _sel.contains(u.id),
                onChanged: (v) => setState(() => v == true ? _sel.add(u.id) : _sel.remove(u.id)),
                secondary: Avatar(u.initials, seed: u.id),
                title: Text(u.name),
                subtitle: Text(u.role == 'admin' ? 'Admin' : 'Staff'),
              ),
          ]),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.check),
        label: Text(widget.chatId == null ? 'Create (${_sel.length})' : 'Add (${_sel.length})'),
      ),
    );
  }
}
