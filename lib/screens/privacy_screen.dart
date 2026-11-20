// Kelmo Scan - document scanner
// Copyright (C) 2026 Kelmo
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../services/backup_service.dart';
import '../theme/app_themes.dart';

/// Plain-language privacy facts + permission status + data export + licences.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _busy = false;

  static const _facts = [
    ('No ads', 'A clean experience, always'),
    ('No tracking', 'No analytics, no telemetry'),
    ('Local scanning', 'Documents are processed on your device'),
    ('No account required', 'Start scanning instantly'),
    ('Offline OCR', 'Text recognition works without internet'),
    ('User-controlled backup', 'You choose where and when to back up'),
  ];

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.create();
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy dashboard')),
      body: Stack(children: [
        ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.of(context).padding.bottom), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: p.accent.withAlpha(28), borderRadius: BorderRadius.circular(p.radius)),
            child: Row(children: [
              Icon(Icons.verified_user_rounded, size: 46, color: p.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Private by default', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
                  Text('Your documents stay on your device.\nSimple. Secure. Yours.', style: TextStyle(color: p.textMuted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(p.radius), border: Border.all(color: p.outline)),
            child: Column(children: [
              for (final f in _facts)
                ListTile(
                  leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF3DA35D)),
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(f.$2, style: TextStyle(color: p.textMuted)),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          Text('Permissions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
          Text('Only the essentials, always under your control.', style: TextStyle(color: p.textMuted)),
          const SizedBox(height: 8),
          FutureBuilder<PermissionStatus>(
            future: Permission.camera.status,
            builder: (_, snap) {
              final ok = snap.data?.isGranted ?? false;
              return ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: p.accent),
                title: const Text('Camera'),
                subtitle: Text('Needed to scan documents', style: TextStyle(color: p.textMuted)),
                trailing: Text(ok ? 'Allowed' : 'Not allowed', style: TextStyle(color: ok ? const Color(0xFF3DA35D) : p.textMuted, fontWeight: FontWeight.w600)),
                onTap: openAppSettings,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.folder_outlined, color: p.accent),
            title: const Text('Storage'),
            subtitle: Text('Scans live in the app\'s private folder — no storage permission needed', style: TextStyle(color: p.textMuted)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export my data'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent), minimumSize: const Size.fromHeight(52)),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Kelmo Scan',
              applicationLegalese: 'Free software (GPLv3). No ads. No tracking.',
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('View open-source licenses'),
          ),
        ]),
        if (_busy) Container(color: Colors.black38, child: Center(child: CircularProgressIndicator(color: p.accent))),
      ]),
    );
  }
}
