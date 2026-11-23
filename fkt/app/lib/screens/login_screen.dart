import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';
import 'onboarding_screens.dart';

/// WhatsApp-style login: your number → SMS code → (new) your name.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(), _code = TextEditingController();
  bool _busy = false, _sent = false;
  String? _err, _info;

  String get _number {
    var d = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('92')) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    return '0$d';
  }

  Future<void> _request() async {
    if (_number.length != 11) { setState(() => _err = 'Type your mobile number, e.g. 3001234567'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      final r = await Api.post('/api/auth/request', {'phone': _number});
      setState(() {
        _sent = true;
        _info = r['via'] == 'sms'
            ? 'We sent an SMS with a 6-digit code to +92 ${_number.substring(1)}.'
            : 'SMS phone is not connected — ask your admin for the 6-digit code.';
      });
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) { setState(() => _err = 'Type the 6-digit code'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      final r = await Api.post('/api/auth/verify', {'phone': _number, 'code': _code.text.trim(), 'device': 'Android'});
      await Session.setLogin(r['token'] as String, r['user'] as Map<String, dynamic>);
      if (!mounted) return;
      context.read<ChatStore>().stop();
      goAfterLogin(context);
    } catch (e) {
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverSettings() async {
    final c = TextEditingController(text: Session.server);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server settings'),
        content: TextField(controller: c, keyboardType: TextInputType.url, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Server address')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, Session.defaultServer), child: const Text('Default')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    var s = v.replaceAll(RegExp(r'/+$'), '');
    if (!s.startsWith('http')) s = 'http://$s';
    await Session.setServer(s);
    try {
      await Api.get('/api/ping');
      if (mounted) toast(context, 'Connected to server ✓');
    } catch (e) {
      if (mounted) toast(context, 'Saved, but cannot reach it: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white, foregroundColor: navy, elevation: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (_) => _serverSettings(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'server', child: Text('Server settings'))],
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
            const KeplerLogo(size: 84),
            const SizedBox(height: 14),
            Text(_sent ? 'Verify your number' : 'Enter your phone number', textAlign: TextAlign.center,
                style: const TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_sent ? (_info ?? '') : 'Kepler Messenger will send an SMS to verify your number.',
                textAlign: TextAlign.center, style: const TextStyle(color: muted)),
            const SizedBox(height: 28),
            if (!_sent)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 56, width: 78, alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD3E1)), borderRadius: BorderRadius.circular(12)),
                  child: const Text('🇵🇰 +92', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phone, autofocus: true, keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 18, letterSpacing: 1),
                    decoration: const InputDecoration(hintText: '300 1234567'),
                    onSubmitted: (_) => _request(),
                  ),
                ),
              ])
            else
              Center(
                child: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _code, autofocus: true, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(hintText: '––––––', counterText: ''),
                    onChanged: (v) { if (v.length == 6) _verify(); },
                  ),
                ),
              ),
            if (_err != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB42318)))),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: waGreen),
              onPressed: _busy ? null : (_sent ? _verify : _request),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(_sent ? 'Verify' : 'Next', style: const TextStyle(fontSize: 17)),
            ),
            if (_sent)
              TextButton(
                onPressed: _busy ? null : () => setState(() { _sent = false; _code.clear(); _err = null; }),
                child: Text('Wrong number? +92 ${_number.substring(1)} — change'),
              ),
          ]),
        ),
      );
}
