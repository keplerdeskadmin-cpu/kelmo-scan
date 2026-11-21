import 'package:flutter/material.dart';
import '../api.dart';
import '../session.dart';
import '../ui.dart';
import 'login_screen.dart';

/// First launch: the address of the FKT server (laptop IP or tunnel link).
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _c = TextEditingController(text: Session.server ?? 'http://192.168.10.16:3100');
  bool _busy = false;
  String? _err;

  Future<void> _go() async {
    var s = _c.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!s.startsWith('http')) s = 'http://$s';
    setState(() { _busy = true; _err = null; });
    final old = Session.server;
    Session.server = s;
    try {
      final r = await Api.get('/api/ping');
      if (r['app'] != 'fkt-messenger') throw ApiError('This is not an FKT Messenger server');
      await Session.setServer(s);
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e) {
      Session.server = old;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.forum_rounded, color: gold, size: 72),
                const SizedBox(height: 12),
                const Text('FKT Messenger', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const Text('Fly Kawn Travel · staff chat', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC8D1E6))),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Server address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('Ask your admin. Example: http://192.168.10.16:3100', style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    TextField(controller: _c, keyboardType: TextInputType.url, autocorrect: false,
                        decoration: InputDecoration(labelText: 'Server', errorText: _err, errorMaxLines: 3)),
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: navy),
                      onPressed: _busy ? null : _go,
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Connect', style: TextStyle(fontSize: 16)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
