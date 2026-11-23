import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// After login: name (new account) → waiting for approval → chats.
void goAfterLogin(BuildContext context) {
  final Widget next = !Session.hasName
      ? const NameScreen()
      : !Session.approved
          ? const PendingScreen()
          : const HomeScreen();
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (_) => false);
}

Future<void> logoutTo(BuildContext context) async {
  try { await Api.post('/api/logout'); } catch (_) {}
  if (!context.mounted) return;
  context.read<ChatStore>().stop();
  await Session.logout();
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

class NameScreen extends StatefulWidget {
  const NameScreen({super.key});
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _name = TextEditingController(), _about = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _save() async {
    if (_name.text.trim().length < 2) { setState(() => _err = 'Please type your name'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      final r = await Api.post('/api/me', {'name': _name.text.trim(), 'about': _about.text.trim()});
      await Session.setMe(r['user'] as Map<String, dynamic>);
      if (mounted) goAfterLogin(context);
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 30),
            const Text('Profile info', textAlign: TextAlign.center, style: TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Type your name so your colleagues know who you are.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
            const SizedBox(height: 28),
            const Center(child: CircleAvatar(radius: 48, backgroundColor: Color(0xFFE6EAF4), child: Icon(Icons.person, size: 56, color: navy))),
            const SizedBox(height: 24),
            TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: _about, decoration: const InputDecoration(labelText: 'Your desk (optional)', hintText: 'e.g. Ticketing, Visa, Accounts', prefixIcon: Icon(Icons.work_outline))),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: Color(0xFFB42318)))),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: waGreen),
              onPressed: _busy ? null : _save,
              child: const Text('Next', style: TextStyle(fontSize: 17)),
            ),
          ]),
        ),
      );
}

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _check() async {
    try {
      final r = await Api.get('/api/me');
      await Session.setMe(r['user'] as Map<String, dynamic>);
      if (Session.approved && mounted) { _t?.cancel(); goAfterLogin(context); }
    } on ApiError catch (e) {
      if (e.code == 401 && mounted) { _t?.cancel(); logoutTo(context); }
    } catch (_) {}
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.hourglass_top_rounded, size: 72, color: gold),
              const SizedBox(height: 16),
              Text('Salam ${Session.me?['name'] ?? ''}!', style: const TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Your account is waiting for the admin to approve it.\nThis page opens your chats automatically once approved.',
                  textAlign: TextAlign.center, style: TextStyle(color: muted)),
              const SizedBox(height: 24),
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 30),
              TextButton(onPressed: () => logoutTo(context), child: const Text('Use another number')),
            ]),
          ),
        ),
      );
}
