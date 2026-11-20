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
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/image_processing_service.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';
import '../widgets/stamp_maker.dart';

// ───────────────────────── model

abstract class _Item {}

class _Stroke extends _Item {
  _Stroke(this.color, this.width, this.opacity);
  final List<Offset> pts = []; // normalised 0..1
  final Color color;
  final double width; // fraction of image width
  final double opacity;
}

class _Stamp extends _Item {
  _Stamp(this.img, this.center, this.widthFrac);
  final ui.Image img;
  Offset center; // normalised
  double widthFrac; // stamp width / image width
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.items, this.imageAspect, {this.selected, this.rev = 0});
  final List<_Item> items;
  final double imageAspect; // image width / height
  final _Stamp? selected;
  final int rev;

  static Rect stampRect(_Stamp s, Size size) {
    final w = s.widthFrac * size.width;
    final h = w * s.img.height / s.img.width;
    return Rect.fromCenter(center: Offset(s.center.dx * size.width, s.center.dy * size.height), width: w, height: h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final it in items) {
      if (it is _Stroke) {
        if (it.pts.isEmpty) continue;
        final paint = Paint()
          ..color = it.color.withAlpha((it.opacity * 255).round())
          ..strokeWidth = it.width * size.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = Path()..moveTo(it.pts.first.dx * size.width, it.pts.first.dy * size.height);
        for (final p in it.pts.skip(1)) { path.lineTo(p.dx * size.width, p.dy * size.height); }
        if (it.pts.length == 1) path.lineTo(it.pts.first.dx * size.width + .1, it.pts.first.dy * size.height);
        canvas.drawPath(path, paint);
      } else if (it is _Stamp) {
        final r = stampRect(it, size);
        canvas.drawImageRect(it.img, Rect.fromLTWH(0, 0, it.img.width.toDouble(), it.img.height.toDouble()), r,
            Paint()..filterQuality = FilterQuality.high);
        if (identical(it, selected)) {
          canvas.drawRect(r.inflate(4), Paint()
            ..color = const Color(0xFF2E9CF0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => true;
}

// ───────────────────────── signatures on disk

class SignatureStore {
  static Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/signatures');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<List<File>> all() async {
    final files = (await _dir()).listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<File> save(Uint8List png) async {
    final f = File('${(await _dir()).path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(png);
    return f;
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _png(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

/// Turns a photo of a signature into ink on a transparent background, cropped to the ink.
Future<Uint8List?> _photoToSignature(String path) async {
  final bw = await ImageProcessingService.instance.applyFilter(path, FilterMode.grayscale, maxSide: 1400);
  final src = await _decode(await File(bw).readAsBytes());
  final raw = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final w = src.width, h = src.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  final out = Uint8List(raw.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final lum = (raw[i] * 299 + raw[i + 1] * 587 + raw[i + 2] * 114) ~/ 1000;
      if (lum < 110) {
        out[i] = 10; out[i + 1] = 20; out[i + 2] = 60; // dark blue-black ink
        out[i + 3] = (255 - lum * 2).clamp(120, 255).toInt();
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  final full = await _fromPixels(out, w, h);
  return _png(await _crop(full, Rect.fromLTRB(minX - 8.0, minY - 8.0, maxX + 9.0, maxY + 9.0)));
}

Future<ui.Image> _fromPixels(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<ui.Image> _crop(ui.Image img, Rect r) {
  final rect = r.intersect(Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()));
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(img, rect, Rect.fromLTWH(0, 0, rect.width, rect.height), Paint());
  return rec.endRecording().toImage(rect.width.ceil(), rect.height.ceil());
}

Future<ui.Image> _textImage(String text, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 96, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 2400);
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(8, 4));
  return rec.endRecording().toImage(tp.width.ceil() + 16, tp.height.ceil() + 8);
}

// ───────────────────────── markup screen

/// Pen, signatures, images and text on a page. Pops the new image path (null = cancelled).
class MarkupScreen extends StatefulWidget {
  const MarkupScreen({super.key, required this.imagePath, this.openStamp = false});
  final String imagePath;
  final bool openStamp; // go straight to the stamp picker
  @override
  State<MarkupScreen> createState() => _MarkupScreenState();
}

class _MarkupScreenState extends State<MarkupScreen> {
  static const _colors = [Colors.white, Color(0xFF6B5B00), Color(0xFF7A0000), Color(0xFFD50000), Color(0xFFFF5722),
    Colors.black, Color(0xFF0D47A1), Color(0xFF2E7D32)];
  final List<_Item> _items = [], _redo = [];
  List<File> _sigs = [];
  double _aspect = .75;
  bool _pen = false, _busy = false;
  Color _color = const Color(0xFFD50000);
  double _size = 21, _opacity = 100;
  _Stamp? _sel;
  _Stroke? _cur;
  // gesture state for moving / scaling a stamp
  Offset? _startFocal, _startCenter;
  double _startW = 0;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    FileImage(File(widget.imagePath)).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) { if (mounted) setState(() => _aspect = info.image.width / info.image.height); }),
    );
    _loadSigs();
    if (widget.openStamp) WidgetsBinding.instance.addPostFrameCallback((_) => _stamp());
  }

  Future<void> _stamp() async {
    final png = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const StampPickerScreen()));
    if (png != null) await _addStamp(await _decode(png), width: .4);
  }

  Future<void> _loadSigs() async {
    final s = await SignatureStore.all();
    if (mounted) setState(() => _sigs = s);
  }

  void _push(_Item it) { _items.add(it); _redo.clear(); }

  Future<void> _addStamp(ui.Image img, {double width = .35}) async {
    final s = _Stamp(img, const Offset(.5, .5), width);
    setState(() { _push(s); _sel = s; _pen = false; });
  }

  Future<void> _addSignatureFile(File f) async => _addStamp(await _decode(await f.readAsBytes()));

  Future<void> _plus() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.draw), title: const Text('Create Signature'), onTap: () => Navigator.pop(ctx, 'create')),
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Scan your signature'), onTap: () => Navigator.pop(ctx, 'scan')),
          ListTile(leading: const Icon(Icons.approval), title: const Text('Stamp'), onTap: () => Navigator.pop(ctx, 'stamp')),
          ListTile(leading: const Icon(Icons.image), title: const Text('Image'), onTap: () => Navigator.pop(ctx, 'image')),
          ListTile(leading: const Icon(Icons.text_fields), title: const Text('Text'), onTap: () => Navigator.pop(ctx, 'text')),
        ]),
      ),
    );
    switch (v) {
      case 'create':
        if (!mounted) return;
        final png = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const SignaturePadScreen()));
        if (png != null) { final f = await SignatureStore.save(png); await _loadSigs(); await _addSignatureFile(f); }
      case 'scan':
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
        if (x == null) return;
        setState(() => _busy = true);
        try {
          final png = await _photoToSignature(x.path);
          if (png == null) { _snack('No signature found — use dark ink on white paper'); return; }
          final f = await SignatureStore.save(png);
          await _loadSigs();
          await _addSignatureFile(f);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case 'stamp':
        await _stamp();
      case 'image':
        final x = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (x != null) await _addStamp(await _decode(await File(x.path).readAsBytes()), width: .45);
      case 'text':
        if (!mounted) return;
        final t = await promptText(context, 'Text', hint: 'Type the text to place');
        if (t != null && t.trim().isNotEmpty) await _addStamp(await _textImage(t.trim(), _color), width: .5);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  _Stamp? _hit(Offset n, Size box) {
    for (final it in _items.reversed) {
      if (it is _Stamp && _MarkPainter.stampRect(it, box).inflate(12).contains(Offset(n.dx * box.width, n.dy * box.height))) return it;
    }
    return null;
  }

  void _undo() { if (_items.isNotEmpty) setState(() { _redo.add(_items.removeLast()); _sel = null; }); }
  void _redoIt() { if (_redo.isNotEmpty) setState(() => _items.add(_redo.removeLast())); }
  void _deleteSel() { if (_sel != null) setState(() { _items.remove(_sel); _sel = null; }); }

  Future<void> _save() async {
    if (_items.isEmpty) { Navigator.pop(context); return; }
    setState(() { _busy = true; _sel = null; });
    try {
      final base = await _decode(await File(widget.imagePath).readAsBytes());
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(base, Offset.zero, Paint());
      _MarkPainter(_items, _aspect).paint(canvas, size);
      final img = await rec.endRecording().toImage(base.width, base.height);
      final tmp = await getTemporaryDirectory();
      final png = File('${tmp.path}/markup_${DateTime.now().microsecondsSinceEpoch}.png');
      await png.writeAsBytes(await _png(img));
      final jpg = await ImageProcessingService.instance.shrink(png.path, 100000, 92);
      if (mounted) Navigator.pop(context, jpg);
    } catch (e) {
      if (mounted) { setState(() => _busy = false); _snack('Could not save: $e'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: const Text('Markup'),
        actions: [
          if (_sel != null) IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: _deleteSel),
          IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: _items.isEmpty ? null : _undo),
          IconButton(icon: const Icon(Icons.redo), tooltip: 'Redo', onPressed: _redo.isEmpty ? null : _redoIt),
          IconButton(icon: const Icon(Icons.check), tooltip: 'Save', onPressed: _busy ? null : _save),
        ],
      ),
      body: Stack(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AspectRatio(
              aspectRatio: _aspect,
              child: LayoutBuilder(builder: (_, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                Offset norm(Offset o) =>
                    Offset((o.dx / size.width).clamp(0.0, 1.0).toDouble(), (o.dy / size.height).clamp(0.0, 1.0).toDouble());
                return GestureDetector(
                  onTapUp: _pen ? null : (d) => setState(() => _sel = _hit(norm(d.localPosition), size)),
                  onScaleStart: (d) {
                    final n = norm(d.localFocalPoint);
                    if (_pen) {
                      _cur = _Stroke(_color, _size / 1000, _opacity / 100)..pts.add(n);
                      setState(() => _push(_cur!));
                    } else {
                      final s = _hit(n, size) ?? _sel;
                      setState(() => _sel = s);
                      if (s != null) { _startFocal = n; _startCenter = s.center; _startW = s.widthFrac; }
                    }
                  },
                  onScaleUpdate: (d) {
                    final n = norm(d.localFocalPoint);
                    if (_pen) {
                      if (_cur != null && d.pointerCount == 1) setState(() { _cur!.pts.add(n); _rev++; });
                    } else if (_sel != null && _startFocal != null) {
                      setState(() {
                        _sel!.center = _startCenter! + (n - _startFocal!);
                        _sel!.widthFrac = (_startW * d.scale).clamp(.05, 1.5).toDouble();
                      });
                    }
                  },
                  onScaleEnd: (_) { _cur = null; _startFocal = null; },
                  child: Stack(children: [
                    Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.fill)),
                    Positioned.fill(child: CustomPaint(painter: _MarkPainter(_items, _aspect, selected: _sel, rev: _rev))),
                  ]),
                );
              }),
            ),
          ),
        ),
        if (_busy) Positioned.fill(child: Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white)))),
      ]),
      bottomNavigationBar: Container(color: p.appBar, child: SafeArea(top: false, child: _pen ? _penPanel() : _sigPanel())),
    );
  }

  Widget _sigPanel() => SizedBox(
        height: 120,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.fromLTRB(12, 8, 0, 4), child: Text('Signatures', style: TextStyle(color: Colors.white, fontSize: 15))),
              Expanded(
                child: _sigs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Tap + to create or scan your signature', style: TextStyle(color: Colors.white70)))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        itemCount: _sigs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _addSignatureFile(_sigs[i]),
                          onLongPress: () async {
                            if (await confirm(context, 'Delete signature?', 'It will be removed from the list.')) {
                              _sigs[i].deleteSync();
                              _loadSigs();
                            }
                          },
                          child: Container(
                            width: 90, color: Colors.white, padding: const EdgeInsets.all(4),
                            child: Image.file(_sigs[i], fit: BoxFit.contain),
                          ),
                        ),
                      ),
              ),
            ]),
          ),
          Container(width: 1, height: 90, color: Colors.white30),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.brush, color: Colors.white), tooltip: 'Pen', onPressed: () => setState(() { _pen = true; _sel = null; })),
            IconButton(icon: const Icon(Icons.add, color: Colors.white, size: 30), tooltip: 'Add', onPressed: _plus),
          ]),
          const SizedBox(width: 6),
        ]),
      );

  Widget _penPanel() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Size', style: TextStyle(color: Colors.white)),
                Expanded(
                  child: Slider(value: _size, min: 2, max: 60, activeColor: const Color(0xFF26A69A),
                      onChanged: (v) => setState(() => _size = v)),
                ),
                SizedBox(width: 26, child: Text('${_size.round()}', style: const TextStyle(color: Colors.white))),
              ]),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 34, height: 34, margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? Colors.white : Colors.white24, width: _color == c ? 3 : 1),
                        ),
                      ),
                    ),
                ]),
              ),
              Row(children: [
                const Icon(Icons.opacity, color: Colors.white, size: 20),
                Expanded(
                  child: Slider(value: _opacity, min: 10, max: 100, activeColor: const Color(0xFF26A69A),
                      onChanged: (v) => setState(() => _opacity = v)),
                ),
                SizedBox(width: 30, child: Text('${_opacity.round()}', style: const TextStyle(color: Colors.white))),
              ]),
            ]),
          ),
          Container(width: 1, height: 110, color: Colors.white30, margin: const EdgeInsets.symmetric(horizontal: 6)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cleaning_services_outlined, color: Colors.white54),
            const SizedBox(height: 10),
            TextButton(onPressed: () => setState(() => _pen = false), child: const Text('DONE', style: TextStyle(color: Colors.white, fontSize: 16))),
          ]),
        ]),
      );
}

// ───────────────────────── signature pad

/// White pad to draw a signature with a finger. Pops a transparent, cropped PNG.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});
  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<List<Offset>> _lines = [];
  Color _ink = const Color(0xFF0D1B4C);
  Size _size = Size.zero;

  Future<void> _done() async {
    if (_lines.isEmpty) { Navigator.pop(context); return; }
    const scale = 3.0, stroke = 4.0;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final l in _lines) {
      for (final p in l) { minX = math.min(minX, p.dx); minY = math.min(minY, p.dy); maxX = math.max(maxX, p.dx); maxY = math.max(maxY, p.dy); }
    }
    final pad = stroke * 2;
    final r = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(scale)..translate(-r.left, -r.top);
    _paintLines(c, _lines, _ink, stroke);
    final img = await rec.endRecording().toImage((r.width * scale).ceil(), (r.height * scale).ceil());
    final png = await _png(img);
    if (mounted) Navigator.pop(context, png);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: const Text('Create Signature'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _lines.isEmpty ? null : () => setState(() => _lines.removeLast())),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _lines.isEmpty ? null : () => setState(_lines.clear)),
          IconButton(icon: const Icon(Icons.check), onPressed: _done),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            _size = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              onPanStart: (d) => setState(() => _lines.add([d.localPosition])),
              onPanUpdate: (d) => setState(() => _lines.last.add(d.localPosition)),
              child: CustomPaint(
                size: _size,
                painter: _PadPainter(_lines, _ink),
                child: Align(
                  alignment: const Alignment(0, .55),
                  child: Container(height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 40), color: Colors.black26),
                ),
              ),
            );
          }),
        ),
        Container(
          color: p.appBar,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Ink:  ', style: TextStyle(color: Colors.white)),
                for (final c in const [Color(0xFF0D1B4C), Colors.black, Color(0xFF0D47A1), Color(0xFFC62828)])
                  GestureDetector(
                    onTap: () => setState(() => _ink = c),
                    child: Container(
                      width: 34, height: 34, margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: _ink == c ? 3 : 1)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

void _paintLines(Canvas c, List<List<Offset>> lines, Color ink, double stroke) {
  final paint = Paint()
    ..color = ink
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final l in lines) {
    if (l.isEmpty) continue;
    final path = Path()..moveTo(l.first.dx, l.first.dy);
    for (final p in l.skip(1)) { path.lineTo(p.dx, p.dy); }
    if (l.length == 1) path.lineTo(l.first.dx + .1, l.first.dy);
    c.drawPath(path, paint);
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.lines, this.ink);
  final List<List<Offset>> lines;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) => _paintLines(canvas, lines, ink, 4);
  @override
  bool shouldRepaint(_PadPainter old) => true;
}
