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

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_lock.dart';
import '../services/app_settings.dart';
import '../services/backup_service.dart';
import '../services/document_repository.dart';
import '../services/ocr_indexer.dart';
import '../services/ocr_service.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';
import '../widgets/theme_picker_sheet.dart';
import 'lock_screen.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = AppSettings.instance;
  bool _busy = false;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    OcrIndexer.refresh();
    AppLock.instance.biometricAvailable().then((v) { if (mounted) setState(() => _bioAvailable = v); });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.create();
      await Share.shareXFiles([XFile(path)]); // pick Drive / Files / WhatsApp … to store it
    } catch (e) {
      _snack('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null || !mounted) return;
    if (!await confirm(context, 'Restore backup?', 'This REPLACES all current documents and folders.', yes: 'Restore')) return;
    setState(() => _busy = true);
    try {
      await BackupService.restore(path);
      unawaited(OcrIndexer.run());
      _snack('Restore complete');
    } catch (e) {
      _snack('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableLock() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SetPinScreen()));
    if (ok == true) {
      if (_bioAvailable) AppLock.instance.biometric = true;
      setState(() {});
      _snack('App lock is ON. There is no PIN recovery - keep a backup.');
    }
  }

  Future<void> _disableLock() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const VerifyPinScreen()));
    if (ok == true) { await AppLock.instance.clearPin(); setState(() {}); }
  }

  Future<void> _changePin() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const VerifyPinScreen()));
    if (ok == true && mounted) {
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SetPinScreen()));
      setState(() {});
    }
  }

  Widget _section(AppPalette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Text(t.toUpperCase(), style: TextStyle(color: p.accent, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Stack(children: [
        ListView(children: [
          _section(p, 'Appearance'),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: p.accent),
            title: const Text('Theme'),
            subtitle: Text(p.name, style: TextStyle(color: p.textMuted)),
            onTap: () => ThemePickerSheet.show(context),
          ),
          _section(p, 'Scanning'),
          SwitchListTile(
            secondary: Icon(Icons.document_scanner_outlined, color: p.accent),
            title: const Text('Auto-capture'),
            subtitle: Text('Capture when the document is steady', style: TextStyle(color: p.textMuted)),
            value: _s.autoCapture,
            activeColor: p.accent,
            onChanged: (v) => setState(() => _s.autoCapture = v),
          ),
          SwitchListTile(
            secondary: Icon(Icons.drive_file_rename_outline, color: p.accent),
            title: const Text('Ask for name when saving'),
            subtitle: Text('Name, folder and tags after each scan', style: TextStyle(color: p.textMuted)),
            value: _s.askName,
            activeColor: p.accent,
            onChanged: (v) => setState(() => _s.askName = v),
          ),
          ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined, color: p.accent),
            title: const Text('Default PDF page size'),
            trailing: DropdownButton<PdfSize>(
              value: _s.pdfSize, underline: const SizedBox(), dropdownColor: p.surface,
              items: [for (final z in PdfSize.values) DropdownMenuItem(value: z, child: Text(z.label))],
              onChanged: (v) { if (v != null) setState(() => _s.pdfSize = v); },
            ),
          ),
          ListTile(
            leading: Icon(Icons.translate_rounded, color: p.accent),
            title: const Text('OCR language'),
            subtitle: Text('Offline (Tesseract)', style: TextStyle(color: p.textMuted)),
            trailing: DropdownButton<String>(
              value: _s.ocrLang, underline: const SizedBox(), dropdownColor: p.surface,
              items: [for (final l in OcrLang.all) DropdownMenuItem(value: l.code, child: Text(l.label))],
              onChanged: (v) { if (v != null) { setState(() => _s.ocrLang = v); _snack('Tap "Rebuild" under Search to re-index with this language'); } },
            ),
          ),
          _section(p, 'Search'),
          ValueListenableBuilder<int>(
            valueListenable: OcrIndexer.pending,
            builder: (_, n, __) => ListTile(
              leading: Icon(Icons.manage_search_rounded, color: p.accent),
              title: const Text('Search inside documents'),
              subtitle: Text(n > 0 ? 'Indexing… $n page(s) left' : 'Index is up to date', style: TextStyle(color: p.textMuted)),
              trailing: TextButton(
                onPressed: () async { await DocumentRepository.instance.resetOcrIndex(); unawaited(OcrIndexer.run()); },
                child: const Text('Rebuild'),
              ),
            ),
          ),
          _section(p, 'Security'),
          SwitchListTile(
            secondary: Icon(Icons.lock_outline_rounded, color: p.accent),
            title: const Text('App lock'),
            subtitle: Text(AppLock.instance.enabled ? 'PIN protected' : 'Protect passports & IDs with a PIN', style: TextStyle(color: p.textMuted)),
            value: AppLock.instance.enabled,
            activeColor: p.accent,
            onChanged: (v) => v ? _enableLock() : _disableLock(),
          ),
          if (AppLock.instance.enabled) ...[
            ListTile(
              leading: Icon(Icons.pin_outlined, color: p.accent),
              title: const Text('Change PIN'),
              onTap: _changePin,
            ),
            if (_bioAvailable)
              SwitchListTile(
                secondary: Icon(Icons.fingerprint, color: p.accent),
                title: const Text('Unlock with fingerprint / face'),
                value: AppLock.instance.biometric,
                activeColor: p.accent,
                onChanged: (v) => setState(() => AppLock.instance.biometric = v),
              ),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: p.accent),
              title: const Text('Lock after'),
              trailing: DropdownButton<int>(
                value: AppLock.instance.timeoutSec, underline: const SizedBox(), dropdownColor: p.surface,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Immediately')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                  DropdownMenuItem(value: 60, child: Text('1 minute')),
                  DropdownMenuItem(value: 300, child: Text('5 minutes')),
                ],
                onChanged: (v) { if (v != null) setState(() => AppLock.instance.timeoutSec = v); },
              ),
            ),
          ],
          SwitchListTile(
            secondary: Icon(Icons.visibility_off_outlined, color: p.accent),
            title: const Text('Hide in recent apps & block screenshots'),
            subtitle: Text('Off while you test with screenshots', style: TextStyle(color: p.textMuted)),
            value: AppLock.instance.secureScreen,
            activeColor: p.accent,
            onChanged: (v) { setState(() => AppLock.instance.secureScreen = v); AppLock.instance.applySecure(); },
          ),
          _section(p, 'Backup'),
          ListTile(
            leading: Icon(Icons.backup_outlined, color: p.accent),
            title: const Text('Create backup'),
            subtitle: Text('One .zip with all documents & folders', style: TextStyle(color: p.textMuted)),
            onTap: _busy ? null : _backup,
          ),
          ListTile(
            leading: Icon(Icons.restore_rounded, color: p.accent),
            title: const Text('Restore from backup'),
            subtitle: Text('Replaces everything currently in the app', style: TextStyle(color: p.textMuted)),
            onTap: _busy ? null : _restore,
          ),
          _section(p, 'Privacy'),
          ListTile(
            leading: Icon(Icons.shield_outlined, color: p.accent),
            title: const Text('Privacy dashboard'),
            subtitle: Text('No ads • No tracking • 100% local', style: TextStyle(color: p.textMuted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
          ),
          _section(p, 'About'),
          ListTile(
            leading: Icon(Icons.info_outline, color: p.accent),
            title: const Text('Kelmo Scan'),
            subtitle: Text('Free & open-source (GPLv3) • No ads • No subscription', style: TextStyle(color: p.textMuted)),
          ),
          const SizedBox(height: 40),
        ]),
        if (_busy)
          Container(color: Colors.black38, child: Center(child: CircularProgressIndicator(color: p.accent))),
      ]),
    );
  }
}
