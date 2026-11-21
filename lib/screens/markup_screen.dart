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
import 'dart:convert';
import '../models/scan_document.dart';
import '../services/document_repository.dart';
import '../services/image_processing_service.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';
import '../widgets/stamp_maker.dart';
import '../widgets/zoom_draw_area.dart';

// ───────────────────────── model

abstract class _Item {}

class _Stroke extends _Item {
  _Stroke(this.color, this.width, this.opacity, {this.mode = 0});
  final List<Offset> pts = []; // normalised 0..1
  final Color color;
  final double width; // fraction of image width
  final double opacity;
  final int mode; // 0 pen, 1 highlighter, 2 blur
}

/// Line / arrow / box / circle.
class _Shape extends _Item {
  _Shape(this.kind, this.a, this.b, this.color, this.width);
  final String kind; // line | arrow | rect | circle
  Offset a, b; // normalised
  final Color color;
  final double width;
}

class _Stamp extends _Item {
  _Stamp(this.img, this.center, this.widthFrac);
  final ui.Image img;
  Offset center; // normalised
  double widthFrac; // stamp width / image width
  double rotation = 0; // radians (two-finger turn)
  double opacity = 1; // 0.1..1 — "light / low" slider
  String? file; // PNG name inside the page's markup folder once saved
}

double _r4(double v) => (v * 10000).roundToDouble() / 10000;

Map<String, Object?> _itemToJson(_Item it) {
  if (it is _Stroke) {
    return {'t': 's', 'c': it.color.toARGB32(), 'w': it.width, 'o': it.opacity, 'm': it.mode,
      'p': [for (final q in it.pts) ...[_r4(q.dx), _r4(q.dy)]]};
  }
  if (it is _Shape) {
    return {'t': 'h', 'k': it.kind, 'a': [it.a.dx, it.a.dy], 'b': [it.b.dx, it.b.dy], 'c': it.color.toARGB32(), 'w': it.width};
  }
  final st = it as _Stamp;
  return {'t': 'i', 'f': st.file, 'x': st.center.dx, 'y': st.center.dy, 'w': st.widthFrac, 'r': st.rotation, 'op': st.opacity};
}

Future<_Item?> _itemFromJson(Map<String, dynamic> j, String dir) async {
  double d(Object? v) => (v as num).toDouble();
  switch (j['t']) {
    case 's':
      final s = _Stroke(Color(j['c'] as int), d(j['w']), d(j['o']), mode: j['m'] as int? ?? 0);
      final p = (j['p'] as List).map((e) => d(e)).toList();
      for (var i = 0; i + 1 < p.length; i += 2) { s.pts.add(Offset(p[i], p[i + 1])); }
      return s;
    case 'h':
      final a = j['a'] as List, b = j['b'] as List;
      return _Shape(j['k'] as String, Offset(d(a[0]), d(a[1])), Offset(d(b[0]), d(b[1])), Color(j['c'] as int), d(j['w']));
    case 'i':
      final f = File('$dir/${j['f']}');
      if (!f.existsSync()) return null;
      final st = _Stamp(await _decode(await f.readAsBytes()), Offset(d(j['x']), d(j['y'])), d(j['w']))
        ..rotation = d(j['r'])
        ..opacity = j['op'] == null ? 1 : d(j['op'])
        ..file = j['f'] as String;
      return st;
  }
  return null;
}

/// Result of the markup screen: the baked image + the editable layers (JSON).
class MarkupResult {
  const MarkupResult(this.image, this.layers);
  final String image, layers;
}

/// Opens markup for a stored page so it stays editable: the page before markup is kept as
/// base.jpg and the drawings / stamps as layers. Returns true when the page changed.
Future<bool> editPageMarkup(BuildContext context, ScanPage pg, {bool stamp = false}) async {
  final repo = DocumentRepository.instance;
  final dir = repo.markupDir(pg)..createSync(recursive: true);
  final base = File('${dir.path}/base.jpg');
  final hasLayers = pg.markup != null && base.existsSync();
  if (!hasLayers) await File(pg.imagePath).copy(base.path);
  imageCache.clear();
  if (!context.mounted) return false;
  final r = await Navigator.push<MarkupResult>(context, MaterialPageRoute(
      builder: (_) => MarkupScreen(imagePath: base.path, openStamp: stamp, layers: hasLayers ? pg.markup : null, layerDir: dir.path)));
  if (r == null) {
    if (!hasLayers && dir.existsSync()) dir.deleteSync(recursive: true);
    return false;
  }
  final thumb = await ImageProcessingService.instance.applyFilter(r.image, FilterMode.original, maxSide: 360);
  await repo.saveMarkup(pg, r.image, thumb, r.layers);
  imageCache.clear();
  return true;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.items, this.imageAspect, {this.selected, this.rev = 0, this.base});
  final List<_Item> items;
  final double imageAspect; // image width / height
  final _Stamp? selected;
  final int rev;
  final ui.Image? base; // page image, needed for the blur brush

  Path _strokePath(_Stroke it, Size size) {
    final path = Path()..moveTo(it.pts.first.dx * size.width, it.pts.first.dy * size.height);
    for (final p in it.pts.skip(1)) { path.lineTo(p.dx * size.width, p.dy * size.height); }
    if (it.pts.length == 1) path.lineTo(it.pts.first.dx * size.width + .1, it.pts.first.dy * size.height);
    return path;
  }

  void _shape(Canvas canvas, _Shape s, Size size) {
    final a = Offset(s.a.dx * size.width, s.a.dy * size.height), b = Offset(s.b.dx * size.width, s.b.dy * size.height);
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.width * size.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    switch (s.kind) {
      case 'rect': canvas.drawRect(Rect.fromPoints(a, b), paint);
      case 'circle': canvas.drawOval(Rect.fromPoints(a, b), paint);
      default:
        canvas.drawLine(a, b, paint);
        if (s.kind == 'arrow' && (b - a).distance > 2) {
          final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
          final len = math.max(paint.strokeWidth * 4, size.width * .03);
          for (final d in [2.6, -2.6]) {
            canvas.drawLine(b, b + Offset(math.cos(ang + d) * len, math.sin(ang + d) * len), paint);
          }
        }
    }
  }

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
        final path = _strokePath(it, size);
        final paint = Paint()
          ..strokeWidth = it.width * size.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        if (it.mode == 2) {
          // blur brush: blurred page image, only inside the stroke
          final all = Offset.zero & size;
          canvas.saveLayer(all, Paint());
          canvas.drawPath(path, paint..color = Colors.black);
          final sigma = size.width * .012;
          canvas.saveLayer(all, Paint()
            ..blendMode = BlendMode.srcIn
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
          if (base != null) {
            canvas.drawImageRect(base!, Rect.fromLTWH(0, 0, base!.width.toDouble(), base!.height.toDouble()), all, Paint());
          } else {
            canvas.drawRect(all, Paint()..color = Colors.grey);
          }
          canvas.restore();
          canvas.restore();
        } else if (it.mode == 1) {
          canvas.drawPath(path, paint
            ..color = it.color.withAlpha(110)
            ..strokeCap = StrokeCap.square
            ..blendMode = BlendMode.multiply);
        } else {
          canvas.drawPath(path, paint..color = it.color.withAlpha((it.opacity * 255).round()));
        }
      } else if (it is _Shape) {
        _shape(canvas, it, size);
      } else if (it is _Stamp) {
        final r = stampRect(it, size);
        canvas.save();
        canvas.translate(r.center.dx, r.center.dy);
        canvas.rotate(it.rotation);
        final local = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
        canvas.drawImageRect(it.img, Rect.fromLTWH(0, 0, it.img.width.toDouble(), it.img.height.toDouble()), local,
            Paint()
              ..filterQuality = FilterQuality.high
              ..color = Color.fromRGBO(255, 255, 255, it.opacity));
        if (identical(it, selected)) {
          canvas.drawRect(local.inflate(4), Paint()
            ..color = const Color(0xFF2E9CF0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
        canvas.restore();
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
  const MarkupScreen({super.key, required this.imagePath, this.openStamp = false, this.layers, this.layerDir});
  final String imagePath; // page WITHOUT markup (base)
  final bool openStamp; // go straight to the stamp picker
  final String? layers; // saved layers to edit again
  final String? layerDir; // folder for stamp PNGs
  @override
  State<MarkupScreen> createState() => _MarkupScreenState();
}

class _MarkupScreenState extends State<MarkupScreen> {
  static const _colors = [Colors.black, Color(0xFFD50000), Color(0xFF0D47A1), Color(0xFF2E7D32), Colors.white,
    Color(0xFFFFEB3B), Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF673AB7),
    Color(0xFF2196F3), Color(0xFF00BCD4), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFFCDDC39), Color(0xFF795548),
    Color(0xFF9E9E9E), Color(0xFF6B5B00), Color(0xFF7A0000)];
  final List<_Item> _items = [], _redo = [];
  List<File> _sigs = [];
  double _aspect = .75;
  bool _pen = false, _busy = false;
  Color _color = const Color(0xFFD50000);
  double _size = 21, _opacity = 100;
  _Stamp? _sel;
  _Stroke? _cur;
  _Shape? _curShape;
  String _tool = 'pen'; // pen | highlight | blur | eraser | line | arrow | rect | circle
  ui.Image? _base; // display copy of the page, for the blur brush
  // gesture state for moving / scaling / turning a stamp
  Offset? _startFocal, _startCenter;
  double _startW = 0, _startRot = 0;
  int _rev = 0;

  Future<void> _loadLayers() async {
    final l = widget.layers, dir = widget.layerDir;
    if (l == null || dir == null) return;
    try {
      final items = <_Item>[];
      for (final j in jsonDecode(l) as List) {
        final it = await _itemFromJson(j as Map<String, dynamic>, dir);
        if (it != null) items.add(it);
      }
      if (mounted) setState(() => _items.addAll(items));
    } catch (_) {}
  }

  Future<void> _loadBase() async {
    final codec = await ui.instantiateImageCodec(await File(widget.imagePath).readAsBytes(), targetWidth: 1400);
    final img = (await codec.getNextFrame()).image;
    if (mounted) setState(() => _base = img);
  }

  /// Eraser: removes the drawing / shape / stamp under the finger.
  void _eraseAt(Offset n, Size box) {
    final r = 18 / box.width;
    _Item? hit;
    for (final it in _items.reversed) {
      if (it is _Stroke && it.pts.any((p) => (p - n).distance < r + it.width / 2)) { hit = it; break; }
      if (it is _Shape) {
        final rect = Rect.fromPoints(it.a, it.b).inflate(r);
        if (rect.contains(n)) { hit = it; break; }
      }
      if (it is _Stamp && _MarkPainter.stampRect(it, box).contains(Offset(n.dx * box.width, n.dy * box.height))) { hit = it; break; }
    }
    if (hit != null) setState(() { _items.remove(hit); _redo.add(hit!); if (identical(hit, _sel)) _sel = null; });
  }

  @override
  void initState() {
    super.initState();
    FileImage(File(widget.imagePath)).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) { if (mounted) setState(() => _aspect = info.image.width / info.image.height); }),
    );
    _loadSigs();
    _loadBase();
    _loadLayers();
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
    if (_items.isEmpty && widget.layers == null) { Navigator.pop(context); return; }
    setState(() { _busy = true; _sel = null; });
    try {
      final base = await _decode(await File(widget.imagePath).readAsBytes());
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(base, Offset.zero, Paint());
      _MarkPainter(_items, _aspect, base: base).paint(canvas, size);
      final img = await rec.endRecording().toImage(base.width, base.height);
      final tmp = await getTemporaryDirectory();
      final png = File('${tmp.path}/markup_${DateTime.now().microsecondsSinceEpoch}.png');
      await png.writeAsBytes(await _png(img));
      final jpg = await ImageProcessingService.instance.shrink(png.path, 100000, 92);
      // layers: stamp images as PNG files next to base.jpg
      final dir = widget.layerDir ?? tmp.path;
      var n = 0;
      for (final it in _items) {
        if (it is _Stamp && it.file == null) {
          it.file = 'st_${DateTime.now().microsecondsSinceEpoch}_${n++}.png';
          await File('$dir/${it.file}').writeAsBytes(await _png(it.img));
        }
      }
      final used = {for (final it in _items) if (it is _Stamp) it.file};
      if (widget.layerDir != null) {
        for (final f in Directory(dir).listSync().whereType<File>()) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith('st_') && !used.contains(name)) f.deleteSync();
        }
      }
      final layers = jsonEncode([for (final it in _items) _itemToJson(it)]);
      if (mounted) Navigator.pop(context, MarkupResult(jpg, layers));
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
        Padding(
          padding: const EdgeInsets.all(10),
          child: ZoomDrawArea(
            aspect: _aspect,
            onTap: _pen ? null : (n, size) => setState(() => _sel = _hit(n, size)),
            onOneStart: (n, size) {
              if (_pen) {
                switch (_tool) {
                  case 'eraser':
                    _eraseAt(n, size);
                  case 'line' || 'arrow' || 'rect' || 'circle':
                    _curShape = _Shape(_tool, n, n, _color, _size / 1500);
                    setState(() => _push(_curShape!));
                  default:
                    final mode = _tool == 'highlight' ? 1 : _tool == 'blur' ? 2 : 0;
                    final w = mode == 0 ? _size / 1000 : _size * 2.2 / 1000;
                    _cur = _Stroke(mode == 1 && _color == Colors.white ? Colors.yellow : _color, w, _opacity / 100, mode: mode)
                      ..pts.add(n);
                    setState(() => _push(_cur!));
                }
              } else {
                final s = _hit(n, size);
                setState(() => _sel = s);
                if (s != null) { _startFocal = n; _startCenter = s.center; }
              }
            },
            onOneUpdate: (n, size) {
              if (_pen) {
                if (_tool == 'eraser') {
                  _eraseAt(n, size);
                } else if (_curShape != null) {
                  setState(() { _curShape!.b = n; _rev++; });
                } else if (_cur != null) {
                  setState(() { _cur!.pts.add(n); _rev++; });
                }
              } else if (_sel != null && _startFocal != null) {
                setState(() => _sel!.center = _startCenter! + (n - _startFocal!));
              }
            },
            onOneEnd: () { _cur = null; _curShape = null; _startFocal = null; },
            onOneCancel: () {
              final it = _cur ?? _curShape;
              if (it != null) setState(() => _items.remove(it));
              _cur = null; _curShape = null; _startFocal = null;
            },
            onTwoStart: (n, size) {
              if (_pen || _sel == null) return false; // two fingers zoom the page
              _startFocal = n; _startCenter = _sel!.center; _startW = _sel!.widthFrac; _startRot = _sel!.rotation;
              return true;
            },
            onTwoUpdate: (n, scale, rot) {
              if (_sel == null || _startFocal == null) return;
              setState(() {
                _sel!.center = _startCenter! + (n - _startFocal!);
                _sel!.widthFrac = (_startW * scale).clamp(.05, 1.5).toDouble();
                _sel!.rotation = _startRot + rot;
              });
            },
            builder: (size) => Stack(children: [
              Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 2000)),
              Positioned.fill(child: CustomPaint(painter: _MarkPainter(_items, _aspect, selected: _sel, rev: _rev, base: _base))),
            ]),
          ),
        ),
        if (_busy) Positioned.fill(child: Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white)))),
      ]),
      bottomNavigationBar: Container(color: p.appBar, child: SafeArea(top: false, child: _pen ? _penPanel() : _sel != null ? _itemPanel() : _sigPanel())),
    );
  }

  /// Selected picture / stamp / signature / text: light-dark (opacity), turn, size, remove.
  Widget _itemPanel() {
    final it = _sel!;
    Widget btn(IconData i, String t, VoidCallback on) => InkWell(
          onTap: on,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, color: Colors.white),
              Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.brightness_low, color: Colors.white70, size: 20),
          const SizedBox(width: 6),
          const Text('Light', style: TextStyle(color: Colors.white)),
          Expanded(
            child: Slider(
              value: it.opacity, min: .1, max: 1, activeColor: const Color(0xFF26A69A),
              onChanged: (v) => setState(() { it.opacity = v; _rev++; }),
            ),
          ),
          const Text('Dark', style: TextStyle(color: Colors.white)),
          SizedBox(width: 44, child: Text(' ${(it.opacity * 100).round()}%', style: const TextStyle(color: Colors.white))),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          btn(Icons.rotate_left, 'Turn left', () => setState(() => it.rotation -= math.pi / 2)),
          btn(Icons.rotate_right, 'Turn right', () => setState(() => it.rotation += math.pi / 2)),
          btn(Icons.remove_circle_outline, 'Smaller', () => setState(() => it.widthFrac = (it.widthFrac * .85).clamp(.05, 1.5).toDouble())),
          btn(Icons.add_circle_outline, 'Bigger', () => setState(() => it.widthFrac = (it.widthFrac * 1.15).clamp(.05, 1.5).toDouble())),
          btn(Icons.delete_outline, 'Remove', _deleteSel),
          btn(Icons.check, 'Done', () => setState(() => _sel = null)),
        ]),
      ]),
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
                            child: Image.file(_sigs[i], fit: BoxFit.contain, cacheWidth: 300),
                          ),
                        ),
                      ),
              ),
            ]),
          ),
          Container(width: 1, height: 90, color: Colors.white30),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.brush, color: Colors.white), tooltip: 'Draw / Highlight / Blur / Shapes',
                onPressed: () => setState(() { _pen = true; _sel = null; })),
            IconButton(icon: const Icon(Icons.add, color: Colors.white, size: 30), tooltip: 'Add', onPressed: _plus),
          ]),
          const SizedBox(width: 6),
        ]),
      );

  Widget _penPanel() {
    const tools = [
      ('pen', Icons.edit, 'Pen'),
      ('highlight', Icons.border_color, 'Highlight'),
      ('blur', Icons.blur_on, 'Blur'),
      ('eraser', Icons.auto_fix_normal, 'Eraser'),
      ('line', Icons.horizontal_rule, 'Line'),
      ('arrow', Icons.north_east, 'Arrow'),
      ('rect', Icons.crop_square, 'Box'),
      ('circle', Icons.circle_outlined, 'Circle'),
    ];
    final colorTool = _tool != 'blur' && _tool != 'eraser';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 58,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final t in tools)
              GestureDetector(
                onTap: () => setState(() => _tool = t.$1),
                child: Container(
                  width: 62, margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: _tool == t.$1 ? Colors.white.withAlpha(45) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(t.$2, color: Colors.white, size: 24),
                    const SizedBox(height: 2),
                    Text(t.$3, style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
        if (_tool != 'eraser')
          Row(children: [
            const SizedBox(width: 8),
            const Text('Size', style: TextStyle(color: Colors.white)),
            Expanded(
              child: Slider(value: _size, min: 2, max: 60, activeColor: const Color(0xFF26A69A),
                  onChanged: (v) => setState(() => _size = v)),
            ),
            SizedBox(width: 26, child: Text('${_size.round()}', style: const TextStyle(color: Colors.white))),
          ])
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Rub over a drawing, shape or stamp to remove it', style: TextStyle(color: Colors.white70)),
          ),
        if (colorTool)
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
          if (_tool == 'pen') ...[
            const SizedBox(width: 8),
            const Icon(Icons.opacity, color: Colors.white, size: 20),
            Expanded(
              child: Slider(value: _opacity, min: 10, max: 100, activeColor: const Color(0xFF26A69A),
                  onChanged: (v) => setState(() => _opacity = v)),
            ),
          ] else
            const Spacer(),
          TextButton(onPressed: () => setState(() => _pen = false), child: const Text('DONE', style: TextStyle(color: Colors.white, fontSize: 16))),
        ]),
      ]),
    );
  }
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
