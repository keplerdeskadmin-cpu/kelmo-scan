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
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/scan_document.dart';
import '../models/scan_recipe.dart';
import '../services/app_settings.dart';
import '../services/document_repository.dart';
import '../services/ocr_indexer.dart';
import '../services/image_processing_service.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';
import '../widgets/quad_painter.dart';
import '../widgets/recipe_picker.dart';
import '../widgets/save_sheet.dart';
import 'edit_scan_screen.dart';

/// Live camera + quad overlay. Collects pages (multi-page mode) and saves them to SQLite.
/// Pops `true` when something was saved.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.folderId, this.addToDocId, this.recipe});
  final int? folderId;     // new documents go into this folder
  final int? addToDocId;   // append pages to an existing document instead
  final ScanRecipe? recipe; // preset to start with (default: last used)
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _svc = ImageProcessingService.instance;
  final List<ScannedPage> _pages = [];
  ScannedPage? _idFront; // ID-card mode: front side waiting for the back
  late ScanRecipe _recipe = widget.recipe ?? ScanRecipe.byName(AppSettings.instance.lastRecipe);
  CameraController? _c;
  List<Offset>? _quad, _prev;
  bool _busy = false, _flash = false, _auto = AppSettings.instance.autoCapture, _capturing = false, _multi = false, _saving = false;
  int _lastMs = 0, _stable = 0, _tab = 0;

  @override
  void initState() {
    super.initState();
    _applyRecipe(_recipe, remember: widget.recipe != null);
    _init();
  }

  void _applyRecipe(ScanRecipe r, {bool remember = true}) {
    _recipe = r;
    _tab = r.twoSided ? 1 : 0;
    _multi = r.multiPage;
    _idFront = null;
    if (remember) AppSettings.instance.lastRecipe = r.kind.name;
  }

  Future<void> _pickRecipe() async {
    final r = await pickRecipe(context, _recipe);
    if (r != null) setState(() => _applyRecipe(r));
  }

  Future<void> _init() async {
    if (!(await Permission.camera.request()).isGranted) {
      if (mounted) Navigator.pop(context, false);
      return;
    }
    final cams = await availableCameras();
    final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
    final c = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    await c.initialize();
    if (!mounted) { await c.dispose(); return; }
    setState(() => _c = c);
    await _startStream();
  }

  Future<void> _startStream() async {
    final c = _c;
    if (c == null || c.value.isStreamingImages) return;
    await c.startImageStream(_onFrame);
  }

  Future<void> _onFrame(CameraImage img) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_busy || _capturing || now - _lastMs < 250) return;
    _busy = true;
    _lastMs = now;
    try {
      final y = img.planes.first;
      final q = await _svc.detectFrame(
        yPlane: y.bytes, width: img.width, height: img.height,
        rowStride: y.bytesPerRow, rotation: _c!.description.sensorOrientation,
      );
      if (!mounted) return;
      _trackStability(q);
      setState(() => _quad = q);
      if (_auto && _stable >= 5 && q != null) _capture();
    } catch (_) {} finally {
      _busy = false;
    }
  }

  void _trackStability(List<Offset>? q) {
    if (q == null) { _stable = 0; _prev = null; return; }
    final p = _prev;
    if (p != null) {
      double m = 0;
      for (int i = 0; i < 4; i++) { final d = (q[i] - p[i]).distance; if (d > m) m = d; }
      _stable = m < .02 ? _stable + 1 : 0;
    }
    _prev = q;
  }

  Future<void> _capture() async {
    final c = _c;
    if (_capturing || c == null) return;
    _capturing = true;
    String? path;
    List<Offset>? corners;
    try {
      await c.stopImageStream();
      path = (await c.takePicture()).path;
      corners = await _svc.detectCorners(path) ?? _quad;
    } catch (_) {}
    if (path != null) { await _openEditor(path, corners); } else { _resume(); }
  }

  Future<void> _openEditor(String path, List<Offset>? corners) async {
    final idMode = _tab == 1;
    final label = idMode ? (_idFront == null ? 'Next: back side' : 'Done') : (_multi ? 'Add Page' : 'Save');
    final sp = await Navigator.push<ScannedPage>(
      context,
      MaterialPageRoute(builder: (_) => EditScanScreen(imagePath: path, initialCorners: corners, initialMode: _recipe.filter, ctaLabel: label)),
    );
    if (!mounted) return;
    if (sp != null) {
      if (idMode) {
        if (_idFront == null) {
          _idFront = sp;                       // now ask for the back side
        } else {
          _pages.add(await _svc.composeIdCard(_idFront!, sp)); // front + back on ONE A4 page
          _idFront = null;
          await _finish();
          return;
        }
      } else {
        _pages.add(sp);
        if (!_multi) { await _finish(); return; }
      }
    }
    _resume();
  }

  void _resume() {
    _stable = 0; _prev = null; _quad = null; _capturing = false;
    if (mounted) setState(() {});
    _startStream();
  }

  Future<void> _finish() async {
    if (_pages.isEmpty || _saving) return;
    SaveResult? meta;
    if (widget.addToDocId == null) {
      final suggested = '${_recipe.label} ${DocumentRepository.dateStamp()}';
      if (AppSettings.instance.askName) {
        meta = await SaveSheet.show(context,
            suggestedName: suggested, pageCount: _pages.length, folderId: widget.folderId, thumbPath: _pages.first.thumbPath);
        if (meta == null) { _resume(); return; }   // user wants to keep scanning
      } else {
        meta = SaveResult(suggested, widget.folderId, const []);
      }
    }
    setState(() => _saving = true);
    final repo = DocumentRepository.instance;
    if (widget.addToDocId != null) {
      await repo.addPages(widget.addToDocId!, _pages);
    } else {
      await repo.createDocument(
          title: meta!.title, folderId: meta.folderId, pages: _pages, kind: _recipe.kind.name, tags: meta.tags);
    }
    unawaited(OcrIndexer.run());
    if (mounted) Navigator.pop(context, true);
  }

  /// Import one or MANY images; each opens in the editor, all end up in one document.
  Future<void> _fromGallery() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    _capturing = true;
    try { await _c?.stopImageStream(); } catch (_) {}
    for (var i = 0; i < files.length; i++) {
      final corners = await _svc.detectCorners(files[i].path);
      if (!mounted) return;
      final last = i == files.length - 1;
      final sp = await Navigator.push<ScannedPage>(
        context,
        MaterialPageRoute(
          builder: (_) => EditScanScreen(
              imagePath: files[i].path, initialCorners: corners, initialMode: _recipe.filter,
              ctaLabel: last ? 'Done' : 'Next (${i + 1}/${files.length})'),
        ),
      );
      if (sp == null) break;                  // cancel → keep what was added so far
      _pages.add(sp);
    }
    if (!mounted) return;
    if (_pages.isNotEmpty) { await _finish(); } else { _resume(); }
  }

  Future<void> _close() async {
    if (_pages.isEmpty || await confirm(context, 'Discard scans?', '${_pages.length} unsaved page(s) will be lost.', yes: 'Discard')) {
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PopScope(
      canPop: _pages.isEmpty,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            Container(
              color: p.appBar, padding: const EdgeInsets.symmetric(horizontal: 4), height: 56,
              child: Row(children: [
                IconButton(icon: Icon(Icons.close, color: p.onAppBar), onPressed: _close),
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _pickRecipe,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_recipe.icon, color: p.accent, size: 22),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(_recipe.label, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.onAppBar, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: p.headingFont)),
                        ),
                        Icon(Icons.arrow_drop_down, color: p.onAppBar),
                      ]),
                    ),
                  ),
                ),
                const Spacer(),
                if (_pages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
                      onPressed: _saving ? null : _finish,
                      icon: const Icon(Icons.check_rounded),
                      label: Text('Done (${_pages.length})'),
                    ),
                  ),
                IconButton(
                  icon: Icon(_flash ? Icons.flash_on : Icons.flash_off, color: p.accent),
                  onPressed: () { setState(() => _flash = !_flash); _c?.setFlashMode(_flash ? FlashMode.torch : FlashMode.off); },
                ),
                IconButton(
                  icon: Icon(Icons.document_scanner_outlined, color: _auto ? p.accent : p.onAppBar.withAlpha(150)),
                  tooltip: 'Auto capture',
                  onPressed: () => setState(() => _auto = !_auto),
                ),
              ]),
            ),
            if (_tab == 1)
              Container(
                width: double.infinity, color: p.accent.withAlpha(40),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_idFront == null ? 'ID Card — scan the FRONT side' : 'Now scan the BACK side',
                    textAlign: TextAlign.center, style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
              ),
            Expanded(
              child: Center(
                child: (_c == null || !_c!.value.isInitialized || _saving)
                    ? CircularProgressIndicator(color: p.accent)
                    : AspectRatio(
                        aspectRatio: 1 / _c!.value.aspectRatio,
                        child: Stack(fit: StackFit.expand, children: [
                          CameraPreview(_c!),
                          CustomPaint(painter: QuadPainter(_quad, p.cropLine, p.cropHandle)),
                        ]),
                      ),
              ),
            ),
            Container(
              color: p.background, height: 44,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (int i = 0; i < 3; i++)
                  GestureDetector(
                    onTap: () => setState(() { _tab = i; _idFront = null; }),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(['Document', 'ID Card', 'Photo'][i], style: TextStyle(fontWeight: FontWeight.w600, color: _tab == i ? p.accent : p.textMuted)),
                      const SizedBox(height: 3),
                      Container(height: 3, width: 40, color: _tab == i ? p.accent : Colors.transparent),
                    ]),
                  ),
              ]),
            ),
            Container(
              color: p.background, padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _side(p, Icons.photo_library_outlined, 'Gallery', false, _fromGallery),
                GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 78, height: 78, padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent, width: 3)),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent, gradient: p.ctaGradient),
                      child: Icon(Icons.photo_camera_rounded, color: p.onAccent, size: 30),
                    ),
                  ),
                ),
                _side(p, Icons.copy_all_rounded, 'Multi-page', _multi, () => setState(() => _multi = !_multi)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _side(AppPalette p, IconData i, String l, bool on, VoidCallback t) => InkWell(
        onTap: t,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? p.accent : p.outline, width: on ? 2.5 : 1), color: on ? p.accent.withAlpha(40) : p.surface),
            child: Icon(i, color: p.accent),
          ),
          const SizedBox(height: 4),
          Text(l, style: TextStyle(color: on ? p.accent : p.text, fontSize: 12)),
        ]),
      );
}
