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
import '../widgets/border_adjust_overlay.dart';

/// The 4 looks shown in the top bar (+ the Color switch).
enum _Look { original, photo, docs, clear }

/// Clear Scanner style editing: 1) Border adjustment, 2) filter + rotate.
/// Pops a [ScannedPage] when the user confirms with ✓.
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
  final String ctaLabel; // e.g. "Next (1/3)" when importing several photos
  @override
  State<EditScanScreen> createState() => _EditScanScreenState();
}

class _EditScanScreenState extends State<EditScanScreen> {
  final _svc = ImageProcessingService.instance;
  static const _full = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  static const _bg = Color(0xFFE4E6E6);

  late String _src = widget.imagePath; // may be rotated in the border step
  late List<Offset> _corners;
  List<Offset>? _detected;
  double _aspect = .75;
  String? _flat, _shown;
  bool _border = true, _busy = false, _compare = false;
  _Look _look = _Look.docs;
  bool _color = true;

  @override
  void initState() {
    super.initState();
    _corners = widget.initialCorners ??
        const [Offset(.08, .08), Offset(.92, .08), Offset(.92, .92), Offset(.08, .92)];
    _detected = widget.initialCorners;
    _fromMode(widget.initialMode);
    _readAspect();
    if (widget.initialCorners == null) _detect();
  }

  void _fromMode(FilterMode m) {
    switch (m) {
      case FilterMode.original: _look = _Look.original;
      case FilterMode.photo: _look = _Look.photo;
      case FilterMode.auto: _look = _Look.docs; _color = true;
      case FilterMode.bw: _look = _Look.docs; _color = false;
      case FilterMode.magicColor: _look = _Look.clear; _color = true;
      case FilterMode.grayscale: _look = _Look.clear; _color = false;
    }
  }

  FilterMode get _mode => switch (_look) {
        _Look.original => FilterMode.original,
        _Look.photo => FilterMode.photo,
        _Look.docs => _color ? FilterMode.auto : FilterMode.bw,
        _Look.clear => _color ? FilterMode.magicColor : FilterMode.grayscale,
      };

  void _readAspect() {
    FileImage(File(_src)).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) setState(() => _aspect = info.image.width / info.image.height);
      }),
    );
  }

  Future<void> _detect() async {
    final q = await _svc.detectCorners(_src);
    if (q != null && mounted) setState(() { _detected = q; _corners = q; });
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  Future<String> _rot(String path, {required bool clockwise}) async {
    var out = await _svc.rotate90(path);
    if (!clockwise) {
      out = await _svc.rotate90(out);
      out = await _svc.rotate90(out);
    }
    return out;
  }

  // ───────── step 1: border
  Future<void> _rotateSource(bool clockwise) async {
    setState(() => _busy = true);
    try {
      _src = await _rot(_src, clockwise: clockwise);
      final c = _corners;
      // Keep the frame on the same part of the page after turning the photo.
      _corners = clockwise
          ? [for (final o in [c[3], c[0], c[1], c[2]]) Offset(1 - o.dy, o.dx)]
          : [for (final o in [c[1], c[2], c[3], c[0]]) Offset(o.dy, 1 - o.dx)];
      _detected = null;
      imageCache.clear();
      _readAspect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyBorder() async {
    setState(() => _busy = true);
    try {
      _flat = await _svc.warp(_src, _corners);
      await _render();
      if (mounted) setState(() => _border = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────── step 2: filter
  Future<void> _render() async {
    final out = await _svc.applyFilter(_flat!, _mode, maxSide: 1800);
    if (mounted) setState(() => _shown = out);
  }

  Future<void> _pick(_Look l) async {
    if (_busy) return;
    setState(() { _look = l; _busy = true; });
    try { await _render(); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _toggleColor() async {
    if (_busy) return;
    setState(() { _color = !_color; _busy = true; });
    try { await _render(); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _rotateFlat(bool clockwise) async {
    if (_flat == null || _busy) return;
    setState(() => _busy = true);
    try {
      _flat = await _rot(_flat!, clockwise: clockwise);
      await _render();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final full = await _svc.applyFilter(_flat!, _mode); // full resolution
    final thumb = await _svc.applyFilter(_flat!, _mode, maxSide: 360);
    if (!mounted) return;
    Navigator.pop(
      context,
      ScannedPage(origPath: _src, finalPath: full, thumbPath: thumb, corners: _corners, filter: _mode.native),
    );
  }

  // ───────── UI
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return PopScope(
      canPop: _border,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => _border = true); },
      child: Scaffold(
        backgroundColor: _border ? Colors.black : _bg,
        appBar: _border ? _borderBar(p) : _filterBar(p),
        body: Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: _border
                    ? BorderAdjustOverlay(
                        key: ValueKey(_src),
                        imagePath: _src, aspect: _aspect, corners: _corners,
                        onChanged: (c) => setState(() => _corners = c))
                    : _shown == null
                        ? const SizedBox()
                        : GestureDetector(
                            onLongPressStart: (_) => setState(() => _compare = true),
                            onLongPressEnd: (_) => setState(() => _compare = false),
                            child: InteractiveViewer(
                              maxScale: 5,
                              child: Image.file(File(_compare && _flat != null ? _flat! : _shown!),
                                  key: ValueKey(_compare ? 'o$_flat' : _shown), gaplessPlayback: true),
                            ),
                          ),
              ),
            ),
          ),
          if (_compare)
            Positioned(
              top: 10, left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: p.appBar,
                child: const Text('Original', style: TextStyle(color: Colors.white)),
              ),
            ),
          if (_busy) Positioned.fill(child: Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: Colors.white)))),
        ]),
        bottomNavigationBar: _bottomBar(p),
      ),
    );
  }

  PreferredSizeWidget _borderBar(AppPalette p) => AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: Text(widget.ctaLabel.startsWith('Next') ? 'Border adjustment  ${widget.ctaLabel.substring(4)}' : 'Border adjustment'),
      );

  PreferredSizeWidget _filterBar(AppPalette p) {
    Widget look(_Look l, IconData i, String t) {
      final sel = _look == l;
      return Expanded(
        child: InkWell(
          onTap: () => _pick(l),
          child: Container(
            color: sel ? Colors.black.withAlpha(60) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, color: Colors.white, size: 26),
              const SizedBox(height: 2),
              Text(t, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: p.appBar,
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      titleSpacing: 0,
      title: Row(children: [
        look(_Look.original, Icons.image_outlined, 'Original'),
        look(_Look.photo, Icons.photo_outlined, 'Photo'),
        look(_Look.docs, Icons.description_outlined, 'Docs'),
        look(_Look.clear, Icons.auto_fix_high, 'Clear'),
        Container(width: 1, height: 44, color: Colors.white38, margin: const EdgeInsets.symmetric(horizontal: 6)),
        Expanded(
          child: InkWell(
            onTap: _look == _Look.docs || _look == _Look.clear ? _toggleColor : null,
            child: Opacity(
              opacity: _look == _Look.docs || _look == _Look.clear ? 1 : .45,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_color ? Icons.palette : Icons.palette_outlined, color: Colors.white, size: 26),
                const SizedBox(height: 2),
                Text(_color ? 'Color' : 'B&W', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bottomBar(AppPalette p) {
    Widget b(IconData i, String tip, VoidCallback? on) => IconButton(
          tooltip: tip, iconSize: 28, color: Colors.white, disabledColor: Colors.white38,
          icon: Icon(i), onPressed: _busy ? null : on,
        );
    return Container(
      color: p.appBar,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            const SizedBox(width: 6),
            if (_border) ...[
              b(Icons.fullscreen_exit, 'Auto detect', () {
                if (_detected != null) { setState(() => _corners = _detected!); } else { _detect(); }
              }),
              b(Icons.fullscreen, 'Full page', () => setState(() => _corners = _full)),
              b(Icons.rotate_left, 'Rotate left', () => _rotateSource(false)),
              b(Icons.rotate_right, 'Rotate right', () => _rotateSource(true)),
              const Spacer(),
              b(Icons.check, 'Next', _applyBorder),
            ] else ...[
              b(Icons.crop, 'Border', () => setState(() => _border = true)),
              b(Icons.rotate_left, 'Rotate left', () => _rotateFlat(false)),
              b(Icons.rotate_right, 'Rotate right', () => _rotateFlat(true)),
              b(Icons.cleaning_services_outlined, 'Eraser', () => _snack('Eraser is coming in the next update')),
              b(Icons.tune, 'Adjust', () => _snack('Brightness / contrast is coming in the next update')),
              const Spacer(),
              b(Icons.check, 'Done', _flat == null ? null : _finish),
            ],
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}
