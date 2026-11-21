import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: Session.me?['name'] as String? ?? '');
  late final _about = TextEditingController(text: Session.me?['about'] as String? ?? '');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await Api.post('/api/me', {'name': _name.text.trim(), 'about': _about.text.trim()});
      await Session.setMe(r['user'] as Map<String, dynamic>);
      if (mounted) toast(context, 'Saved');
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    try { await Api.post('/api/logout'); } catch (_) {}
    if (!mounted) return;
    context.read<ChatStore>().stop();
    await Session.logout();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final me = Session.me ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Avatar((me['name'] as String? ?? '?').isEmpty ? '?' : (me['name'] as String).substring(0, 1).toUpperCase(), size: 90, seed: Session.myId)),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 12),
        TextField(controller: _about, decoration: const InputDecoration(labelText: 'About (e.g. Ticketing desk)', prefixIcon: Icon(Icons.info_outline))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: navy),
            child: const Text('Save')),
        const SizedBox(height: 24),
        ListTile(leading: const Icon(Icons.phone), title: Text('+${me['phone'] ?? ''}'), subtitle: const Text('Phone')),
        ListTile(leading: const Icon(Icons.dns), title: Text(Session.server ?? ''), subtitle: const Text('Server')),
        ListTile(leading: const Icon(Icons.badge), title: Text(me['role'] == 'admin' ? 'Admin' : 'Staff'), subtitle: const Text('Role')),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFFB42318)),
          title: const Text('Log out', style: TextStyle(color: Color(0xFFB42318))),
          onTap: _logout,
        ),
      ]),
    );
  }
}
