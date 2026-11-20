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
import '../widgets/pdf_settings_dialog.dart';
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
        padding: const EdgeInsets.fromLTRB(72, 20, 20, 6),
        child: Text(t, style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.w600)),
      );

  /// Clear Scanner preference row: title + summary, optional checkbox on the right.
  Widget _pref(AppPalette p, String title, {String? summary, IconData? icon, VoidCallback? onTap, bool? check, ValueChanged<bool>? onCheck}) =>
      ListTile(
        leading: SizedBox(width: 40, child: icon == null ? null : Icon(icon, color: const Color(0xFF5F6666))),
        title: Text(title, style: const TextStyle(fontSize: 16, color: Color(0xFF202124))),
        subtitle: summary == null ? null : Text(summary, style: const TextStyle(fontSize: 14, color: Color(0xFF6F7777))),
        trailing: check == null ? null : Checkbox(value: check, activeColor: p.accent, onChanged: (v) => onCheck?.call(v ?? false)),
        onTap: check != null ? () => onCheck?.call(!check) : onTap,
      );

  Widget _list(AppPalette p, String title, Map<String, String> opts, String cur, ValueChanged<String> set, {IconData? icon}) =>
      _pref(p, title, summary: opts[cur], icon: icon, onTap: () async {
        final v = await pickOption(context, title, opts, cur);
        if (v != null) setState(() => set(v));
      });

  Future<void> _docName() async {
    final ctl = TextEditingController(text: _s.docNamePrefix);
    var date = _s.docNameDate, time = _s.docNameTime;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Document Name'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Name')),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: date, title: const Text('Date'), onChanged: (v) => set(() => date = v!)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: time, title: const Text('Time'), onChanged: (v) => set(() => time = v!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true) setState(() { _s.docNamePrefix = ctl.text; _s.docNameDate = date; _s.docNameTime = time; });
  }

  Future<void> _text(String title, String cur, ValueChanged<String> set, {String hint = ''}) async {
    final v = await promptText(context, title, initial: cur, hint: hint);
    if (v != null) setState(() => set(v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const fmt = {'id': 'Page ID only', 'id_dt': 'Page ID + date & time', 'dt_id': 'Date & time + Page ID'};
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: p.appBar, title: const Text('Settings')),
      body: Stack(children: [
        ListView(children: [
          _section(p, 'Theme'),
          _pref(p, 'Choose theme', summary: p.name, icon: Icons.palette, onTap: () => ThemePickerSheet.show(context)),

          _section(p, 'Scan'),
          _pref(p, 'Use in-app camera (batch scan support)', icon: Icons.photo_camera,
              summary: _s.useInAppCamera ? 'In-app camera' : "Phone's camera app",
              check: _s.useInAppCamera, onCheck: (v) => setState(() => _s.useInAppCamera = v)),
          if (_s.useInAppCamera)
            _list(p, 'Camera Engine', const {'camerax': 'CameraX (Recommended)', 'camera1': 'Camera1 (Legacy)'}, _s.cameraEngine,
                (v) => _s.cameraEngine = v, icon: Icons.camera),
          _pref(p, 'Shutter sound', icon: Icons.volume_up, check: _s.shutterSound, onCheck: (v) => setState(() => _s.shutterSound = v)),
          _pref(p, 'Auto-capture', icon: Icons.document_scanner, summary: 'Capture when the document is steady',
              check: _s.autoCapture, onCheck: (v) => setState(() => _s.autoCapture = v)),
          _list(p, 'Image Picker for Scanning', const {'inapp': 'In-app', 'system': 'System'}, _s.imagePicker,
              (v) => _s.imagePicker = v, icon: Icons.photo_library),
          _list(p, 'Image Quality', const {'low': 'Low', 'medium': 'Medium', 'high': 'High'}, _s.imageQuality,
              (v) => _s.imageQuality = v, icon: Icons.high_quality),
          _pref(p, 'Auto-save to Gallery', icon: Icons.save_alt, summary: 'Save scanned images to Pictures/Kelmo Scan',
              check: _s.autoSaveToGallery, onCheck: (v) => setState(() => _s.autoSaveToGallery = v)),
          if (_s.autoSaveToGallery)
            _list(p, 'Auto-save file name format', fmt, _s.galleryNameFormat, (v) => _s.galleryNameFormat = v, icon: Icons.label),
          _pref(p, 'Ask for name when saving', icon: Icons.drive_file_rename_outline, summary: 'Name, folder and tags after each scan',
              check: _s.askName, onCheck: (v) => setState(() => _s.askName = v)),

          _section(p, 'PDF'),
          _pref(p, 'Document Name', icon: Icons.title, summary: _s.newDocumentName(), onTap: _docName),
          _list(p, 'Page Size', {for (final z in PdfSize.values) z.name: z.label}, _s.pdfSize.name,
              (v) => _s.pdfSize = PdfSize.values.byName(v), icon: Icons.description),
          _list(p, 'Resolution', pdfResolutionLabels, _s.pdfResolution, (v) => _s.pdfResolution = v, icon: Icons.photo_size_select_large),
          _list(p, 'Page Orientation', pdfOrientationLabels, _s.pdfOrientation, (v) => _s.pdfOrientation = v, icon: Icons.screen_rotation),
          _list(p, 'Image Scale', pdfScaleLabels, _s.pdfScale, (v) => _s.pdfScale = v, icon: Icons.aspect_ratio),

          _section(p, 'Default Email'),
          _pref(p, 'To', icon: Icons.email, summary: _s.emailTo.isEmpty ? 'Not set' : _s.emailTo,
              onTap: () => _text('To', _s.emailTo, (v) => _s.emailTo = v, hint: 'name@example.com')),
          _pref(p, 'Subject', icon: Icons.subject, summary: _s.emailSubject.isEmpty ? 'Document name' : _s.emailSubject,
              onTap: () => _text('Subject', _s.emailSubject, (v) => _s.emailSubject = v, hint: 'Empty = document name')),

          _section(p, 'OCR'),
          _list(p, 'Language', {for (final l in OcrLang.all) l.code: l.label}, _s.ocrLang, (v) {
            _s.ocrLang = v;
            _snack('Tap "Rebuild" under Search to re-index with this language');
          }, icon: Icons.translate),

          _section(p, 'Sync to Cloud'),
          _pref(p, 'Sync Settings', icon: Icons.cloud, summary: _s.autoSync ? 'AutoSync on' : 'AutoSync off',
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncSettingsScreen()));
                setState(() {});
              }),

          _section(p, 'Search'),
          ValueListenableBuilder<int>(
            valueListenable: OcrIndexer.pending,
            builder: (_, n, __) => ListTile(
              leading: const SizedBox(width: 40, child: Icon(Icons.manage_search_rounded, color: Color(0xFF5F6666))),
              title: const Text('Search inside documents'),
              subtitle: Text(n > 0 ? 'Indexing… $n page(s) left' : 'Index is up to date', style: TextStyle(color: p.textMuted)),
              trailing: TextButton(
                onPressed: () async { await DocumentRepository.instance.resetOcrIndex(); unawaited(OcrIndexer.run()); },
                child: const Text('Rebuild'),
              ),
            ),
          ),

          _section(p, 'Security'),
          _pref(p, 'App lock', icon: Icons.lock,
              summary: AppLock.instance.enabled ? 'PIN protected' : 'Protect passports & IDs with a PIN',
              check: AppLock.instance.enabled, onCheck: (v) => v ? _enableLock() : _disableLock()),
          if (AppLock.instance.enabled) ...[
            _pref(p, 'Change PIN', icon: Icons.pin, onTap: _changePin),
            if (_bioAvailable)
              _pref(p, 'Unlock with fingerprint / face', icon: Icons.fingerprint,
                  check: AppLock.instance.biometric, onCheck: (v) => setState(() => AppLock.instance.biometric = v)),
            _list(p, 'Lock after', const {'0': 'Immediately', '30': '30 seconds', '60': '1 minute', '300': '5 minutes'},
                '${AppLock.instance.timeoutSec}', (v) => AppLock.instance.timeoutSec = int.parse(v), icon: Icons.timer),
          ],
          _pref(p, 'Hide in recent apps & block screenshots', icon: Icons.visibility_off,
              check: AppLock.instance.secureScreen, onCheck: (v) {
                setState(() => AppLock.instance.secureScreen = v);
                AppLock.instance.applySecure();
              }),

          _section(p, 'Backup'),
          _pref(p, 'Backup file', icon: Icons.backup, summary: 'One .zip with all documents & folders', onTap: _busy ? null : _backup),
          _pref(p, 'Restore', icon: Icons.restore, summary: 'Replaces everything currently in the app', onTap: _busy ? null : _restore),

          _section(p, 'About'),
          _pref(p, 'Privacy dashboard', icon: Icons.shield, summary: 'No ads • No tracking • 100% local',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()))),
          _pref(p, 'Kelmo Scan', icon: Icons.info, summary: 'Free & open-source (GPLv3) • No ads • No subscription'),
          const SizedBox(height: 40),
        ]),
        if (_busy) Container(color: Colors.black38, child: Center(child: CircularProgressIndicator(color: p.accent))),
      ]),
    );
  }
}

/// Sync to Cloud → Sync Settings (same three options as Clear Scanner).
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});
  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _s = AppSettings.instance;

  Widget _row(AppPalette p, String t, String sub, bool v, ValueChanged<bool> set) => CheckboxListTile(
        activeColor: p.accent,
        title: Text(t, style: const TextStyle(fontSize: 16)),
        subtitle: Text(sub, style: const TextStyle(color: Color(0xFF6F7777))),
        value: v,
        onChanged: (x) => setState(() => set(x ?? false)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: p.appBar, title: const Text('Sync Settings')),
      body: ListView(children: [
        _row(p, 'Enable AutoSync', 'Back up new and changed documents automatically', _s.autoSync, (v) => _s.autoSync = v),
        _row(p, 'AutoSync over WiFi only', 'Do not use mobile data', _s.syncWifiOnly, (v) => _s.syncWifiOnly = v),
        _row(p, 'Warn If Sync on Mobile Network', 'Ask before syncing over mobile data', _s.syncWarnMobile, (v) => _s.syncWarnMobile = v),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Sync Now (cloud button on the home screen) makes a backup file you can save to Google Drive or Dropbox.',
              style: TextStyle(color: Color(0xFF6F7777))),
        ),
      ]),
    );
  }
}
