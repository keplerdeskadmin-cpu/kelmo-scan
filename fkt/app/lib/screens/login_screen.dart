import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';
import 'home_screen.dart';
import 'server_screen.dart';

/// Phone number → 6-digit code (SMS, or from the admin panel).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(), _code = TextEditingController();
  bool _busy = false, _sent = false;
  String? _err, _info;

  Future<void> _request() async {
    setState(() { _busy = true; _err = null; });
    try {
      final r = await Api.post('/api/auth/request', {'phone': _phone.text});
      setState(() {
        _sent = true;
        _info = r['via'] == 'sms' ? 'Code sent by SMS.' : 'Ask your admin for the 6-digit code (shown in the admin panel).';
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _err = null; });
    try {
      final r = await Api.post('/api/auth/verify', {'phone': _phone.text, 'code': _code.text, 'device': 'Android'});
      await Session.setLogin(r['token'] as String, r['user'] as Map<String, dynamic>);
      if (!mounted) return;
      final store = context.read<ChatStore>();
      store.stop();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } catch (e) {
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
                const Icon(Icons.forum_rounded, color: gold, size: 64),
                const SizedBox(height: 10),
                const Text('Log in', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _phone, enabled: !_sent, keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Your phone number', hintText: '03xx xxxxxxx', prefixIcon: Icon(Icons.phone)),
                    ),
                    if (_sent) ...[
                      const SizedBox(height: 12),
                      Text(_info ?? '', style: const TextStyle(color: muted)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _code, keyboardType: TextInputType.number, maxLength: 6, autofocus: true,
                        style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                      ),
                    ],
                    if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: Color(0xFFB42318)))),
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: navy),
                      onPressed: _busy ? null : (_sent ? _verify : _request),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(_sent ? 'Verify' : 'Send code', style: const TextStyle(fontSize: 16)),
                    ),
                    if (_sent)
                      TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _code.clear(); }), child: const Text('Change number / resend')),
                  ]),
                ),
                TextButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ServerScreen()), (_) => false),
                  child: Text('Server: ${Session.server ?? ''}', style: const TextStyle(color: Color(0xFFC8D1E6))),
                ),
              ]),
            ),
          ),
        ),
      );
}
