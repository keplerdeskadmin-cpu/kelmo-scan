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

import 'dart:io';
import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/image_processing_service.dart';
import '../theme/app_themes.dart';
import '../widgets/crop_overlay.dart';
import '../widgets/cta_button.dart';
import '../widgets/ocr_sheet.dart';

/// Crop-adjust → filter → OCR. Pops a [ScannedPage] when the user confirms.
class EditScanScreen extends StatefulWidget {
  const EditScanScreen({
    super.key,
    required this.imagePath,
    this.initialCorners,
    this.initialMode = FilterMode.auto,
    this.ctaLabel = 'Save',
  });
  final String imagePath;
  final List<Offset>? initialCorners;
  final FilterMode initialMode;
  final String ctaLabel;
  @override
  State<EditScanScreen> createState() => _EditScanScreenState();
}

class _EditScanScreenState extends State<EditScanScreen> {
  final _svc = ImageProcessingService.instance;
  late List<Offset> _corners;
  late FilterMode _mode = widget.initialMode;
  double _aspect = .75;
  String? _flat, _shown;
  final Map<FilterMode, String> _thumbs = {};
  bool _cropping = true, _busy = false, _compare = false;

  @override
  void initState() {
    super.initState();
    _corners = widget.initialCorners ??
        const [Offset(.08, .08), Offset(.92, .08), Offset(.92, .92), Offset(.08, .92)];
    FileImage(File(widget.imagePath)).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) setState(() => _aspect = info.image.width / info.image.height);
      }),
    );
    if (widget.initialCorners == null) {
      _svc.detectCorners(widget.imagePath).then((q) { if (q != null && mounted) setState(() => _corners = q); });
    }
  }

  Future<void> _applyCrop() async {
    setState(() => _busy = true);
    _flat = await _svc.warp(widget.imagePath, _corners);
    await _rebuildThumbs();
    await _setMode(_mode);
    if (mounted) setState(() { _cropping = false; _busy = false; });
  }

  Future<void> _rebuildThumbs() async {
    _thumbs.clear();
    for (final m in FilterMode.values) {
      _thumbs[m] = await _svc.applyFilter(_flat!, m, maxSide: 200);
      if (mounted) setState(() {});
    }
  }

  Future<void> _setMode(FilterMode m) async {
    setState(() { _mode = m; _busy = true; });
    final out = await _svc.applyFilter(_flat!, m, maxSide: 1800);
    if (mounted) setState(() { _shown = out; _busy = false; });
  }

  Future<void> _rotate() async {
    if (_flat == null) return;
    setState(() => _busy = true);
    _flat = await _svc.rotate90(_flat!);
    await _rebuildThumbs();
    await _setMode(_mode);
  }

  Future<void> _finish() async {
    if (_flat == null) await _applyCrop();
    setState(() => _busy = true);
    final full = await _svc.applyFilter(_flat!, _mode);              // full resolution
    final thumb = await _svc.applyFilter(_flat!, _mode, maxSide: 360);
    if (!mounted) return;
    Navigator.pop(
      context,
      ScannedPage(origPath: widget.imagePath, finalPath: full, thumbPath: thumb, corners: _corners, filter: _mode.native),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Scan')),
      body: Column(children: [
        Expanded(
          child: Container(
            width: double.infinity, color: p.surfaceAlt, padding: const EdgeInsets.all(14),
            child: Stack(alignment: Alignment.center, children: [
              Center(
                child: _cropping
                    ? CropOverlay(imagePath: widget.imagePath, aspect: _aspect, corners: _corners, onChanged: (c) => setState(() => _corners = c))
                    : (_shown == null
                        ? const SizedBox()
                        : GestureDetector(
                            onLongPressStart: (_) => setState(() => _compare = true),
                            onLongPressEnd: (_) => setState(() => _compare = false),
                            child: InteractiveViewer(
                              child: Image.file(File(_compare && _flat != null ? _flat! : _shown!), key: ValueKey(_compare ? 'orig' : _shown)),
                            ),
                          )),
              ),
              if (_busy) Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: p.accent))),
              if (_compare)
                Positioned(top: 4, left: 4, child: Chip(label: const Text('Original'), backgroundColor: p.accent, labelStyle: TextStyle(color: p.onAccent))),
            ]),
          ),
        ),
        Container(
          color: p.background,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_cropping) SizedBox(height: 104, child: _filterStrip(p)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _tool(p, Icons.crop_rounded, _cropping ? 'Apply' : 'Crop', _cropping ? _applyCrop : () => setState(() => _cropping = true)),
                _tool(p, Icons.rotate_right_rounded, 'Rotate', _rotate),
                _tool(p, Icons.auto_awesome, 'Enhance', _flat == null ? null : () => _setMode(FilterMode.magicColor)),
                _tool(p, Icons.text_fields_rounded, 'OCR', _flat == null ? null : () => OcrSheet.show(context, [_flat!])),
                _tool(p, Icons.close_rounded, 'Cancel', () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 10),
              CtaButton(label: widget.ctaLabel, icon: Icons.check_rounded, onTap: _busy ? null : _finish),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _filterStrip(AppPalette p) => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FilterMode.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final m = FilterMode.values[i];
          final sel = m == _mode;
          final t = _thumbs[m];
          return GestureDetector(
            onTap: () => _setMode(m),
            child: Column(children: [
              Container(
                width: 64, height: 76, padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? p.accent : p.outline, width: sel ? 2.5 : 1)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: t == null ? Container(color: p.surfaceAlt) : Image.file(File(t), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 4),
              Text(m.label, style: TextStyle(fontSize: 12, color: sel ? p.accent : p.textMuted, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
            ]),
          );
        },
      );

  Widget _tool(AppPalette p, IconData i, String l, VoidCallback? t) => InkWell(
        onTap: t,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 28, color: t == null ? p.textMuted.withAlpha(110) : p.text),
            const SizedBox(height: 2),
            Text(l, style: TextStyle(fontSize: 13, color: p.text)),
          ]),
        ),
      );
}
