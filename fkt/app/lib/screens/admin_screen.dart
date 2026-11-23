import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../models.dart';
import '../session.dart';
import '../store.dart';
import '../ui.dart';

/// Admins: approve new staff, turn accounts off/on, and make this phone the SMS sender.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true, _needApproval = true, _gwOnline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/api/staff');
      setState(() {
        _users = [for (final u in r['users'] as List) u as Map<String, dynamic>];
        _needApproval = r['requireApproval'] != false;
        _gwOnline = r['gatewayOnline'] == true;
      });
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String id, Map<String, dynamic> body) async {
    try {
      await Api.post('/api/staff/$id', body);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _gateway(bool on) async {
    final store = context.read<ChatStore>();
    if (on) {
      final st = await Permission.sms.request();
      if (!st.isGranted) {
        if (mounted) toast(context, 'SMS permission is needed to send login codes');
        return;
      }
    }
    store.setGateway(on);
    await Future.delayed(const Duration(milliseconds: 600));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ChatStore>();
    final pending = _users.where((u) => u['approved'] == false && u['disabled'] != true).toList();
    final staff = _users.where((u) => u['approved'] != false || u['disabled'] == true).toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Column(children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.sms, color: waGreen),
                      title: const Text('SMS sender (this phone)', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(Session.smsGateway
                          ? (s.gatewayOn ? 'ON — login codes go out from this phone\'s SIM. Keep the app open. Sent: ${s.smsSent}'
                              : 'Turning on… (needs connection to the server)')
                          : (_gwOnline ? 'Another admin phone is sending SMS' : 'OFF — codes show in the admin panel on the laptop')),
                      value: Session.smsGateway,
                      onChanged: _gateway,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user, color: navy),
                      title: const Text('New accounts need my approval'),
                      value: _needApproval,
                      onChanged: (v) async {
                        try { await Api.post('/api/settings', {'requireApproval': v}); } catch (_) {}
                        _load();
                      },
                    ),
                  ]),
                ),
                if (pending.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('WAITING FOR APPROVAL', style: TextStyle(color: Color(0xFFB54708), fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  for (final u in pending)
                    ListTile(
                      leading: Avatar(AppUser.fromJson(u).initials, seed: u['id'] as String),
                      title: Text(('${u['name']}').isEmpty ? '(no name yet)' : '${u['name']}'),
                      subtitle: Text('+${u['phone']}'),
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(tooltip: 'Reject', icon: const Icon(Icons.close, color: Color(0xFFB42318)),
                            onPressed: () => _set(u['id'] as String, {'disabled': true})),
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: waGreen),
                            onPressed: () => _set(u['id'] as String, {'approved': true}), child: const Text('Approve')),
                      ]),
                    ),
                  const Divider(),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('STAFF (${staff.length})', style: const TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                for (final u in staff)
                  ListTile(
                    leading: Avatar(AppUser.fromJson(u).initials, seed: u['id'] as String, online: u['online'] == true),
                    title: Text('${u['name']}${u['id'] == Session.myId ? ' (you)' : ''}'),
                    subtitle: Text('+${u['phone']} · ${u['role'] == 'admin' ? 'Admin' : 'Staff'}${u['disabled'] == true ? ' · OFF' : ''}'),
                    trailing: u['id'] == Session.myId
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) => _set(u['id'] as String, switch (v) {
                              'off' => {'disabled': true},
                              'on' => {'disabled': false, 'approved': true},
                              'admin' => {'role': 'admin'},
                              _ => {'role': 'staff'},
                            }),
                            itemBuilder: (_) => [
                              if (u['disabled'] == true) const PopupMenuItem(value: 'on', child: Text('Turn on'))
                              else const PopupMenuItem(value: 'off', child: Text('Turn off')),
                              if (u['role'] == 'admin') const PopupMenuItem(value: 'staff', child: Text('Make staff'))
                              else const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                            ],
                          ),
                  ),
                const SizedBox(height: 30),
              ]),
            ),
    );
  }
}
