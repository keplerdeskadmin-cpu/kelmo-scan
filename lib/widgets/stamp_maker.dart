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
import 'dialogs.dart';

// ───────────────────────── stamp design + drawing

const stampColors = <Color>[Color(0xFFC62828), Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A), Color(0xFF212121)];

class StampSpec {
  const StampSpec({this.top = '', this.middle = '', this.bottom = '', this.shape = 'rect', this.color = 0xFFC62828, this.date = false});
  final String top, middle, bottom;
  final String shape; // rect | round
  final int color;
  final bool date;

  StampSpec copyWith({String? top, String? middle, String? bottom, String? shape, int? color, bool? date}) => StampSpec(
      top: top ?? this.top, middle: middle ?? this.middle, bottom: bottom ?? this.bottom,
      shape: shape ?? this.shape, color: color ?? this.color, date: date ?? this.date);

  String get key => '$top|$middle|$bottom|$shape|$color|$date';
}

String _today() {
  const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')} ${m[n.month - 1]} ${n.year}';
}

TextPainter _tp(String t, double size, Color c, {FontWeight w = FontWeight.w800, double spacing = 2}) => TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: c, fontSize: size, fontWeight: w, letterSpacing: spacing, height: 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();

/// Draws the stamp as a transparent PNG.
Future<Uint8List> renderStamp(StampSpec s) async {
  final c = Color(s.color).withAlpha(225);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  late int w, h;
  final date = s.date ? _today() : '';
  if (s.shape == 'round') {
    const d = 720.0;
    w = h = d.toInt();
    final ctr = const Offset(d / 2, d / 2);
    final ring = Paint()..color = c..style = PaintingStyle.stroke;
    canvas.drawCircle(ctr, d / 2 - 12, ring..strokeWidth = 14);
    canvas.drawCircle(ctr, d / 2 - 36, ring..strokeWidth = 5);
    canvas.drawCircle(ctr, d / 2 - 150, ring..strokeWidth = 5);
    _arcText(canvas, s.top.toUpperCase(), ctr, d / 2 - 93, true, c);
    _arcText(canvas, s.bottom.toUpperCase(), ctr, d / 2 - 93, false, c);
    final lines = [if (s.middle.isNotEmpty) s.middle.toUpperCase(), if (date.isNotEmpty) date];
    if (lines.isEmpty) lines.add('★');
    final maxW = (d / 2 - 165) * 2 * .92;
    final tps = <TextPainter>[];
    for (var i = 0; i < lines.length; i++) {
      var size = i == 0 && s.middle.isNotEmpty ? 84.0 : 50.0;
      var tp = _tp(lines[i], size, c, spacing: 1);
      while (tp.width > maxW && size > 20) { size -= 4; tp = _tp(lines[i], size, c, spacing: 1); }
      tps.add(tp);
    }
    var y = ctr.dy - tps.fold<double>(0, (a, t) => a + t.height) / 2;
    for (final tp in tps) { tp.paint(canvas, Offset(ctr.dx - tp.width / 2, y)); y += tp.height; }
  } else {
    final lines = <TextPainter>[
      if (s.top.isNotEmpty) _tp(s.top.toUpperCase(), 54, c),
      if (s.middle.isNotEmpty) _tp(s.middle.toUpperCase(), 120, c, w: FontWeight.w900, spacing: 6),
      if (s.bottom.isNotEmpty) _tp(s.bottom.toUpperCase(), 54, c),
      if (date.isNotEmpty) _tp(date, 54, c),
    ];
    if (lines.isEmpty) lines.add(_tp('STAMP', 120, c, w: FontWeight.w900));
    const pad = 54.0;
    final bw = lines.map((t) => t.width).reduce(math.max) + pad * 2;
    final bh = lines.fold<double>(0, (a, t) => a + t.height) + pad * 2 - 10;
    w = bw.ceil();
    h = bh.ceil();
    final p = Paint()..color = c..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(8, 8, bw - 16, bh - 16), const Radius.circular(26)), p..strokeWidth = 14);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(26, 26, bw - 52, bh - 52), const Radius.circular(14)), p..strokeWidth = 4);
    var y = pad - 5;
    for (final t in lines) { t.paint(canvas, Offset((bw - t.width) / 2, y)); y += t.height; }
  }
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// Text around the ring: on top it reads left→right over the top, at the bottom left→right under.
void _arcText(Canvas canvas, String text, Offset ctr, double r, bool top, Color c) {
  if (text.isEmpty) return;
  var size = 58.0;
  List<TextPainter> chars() => [for (final ch in text.split('')) _tp(ch, size, c, spacing: 0)];
  var cs = chars();
  double total() => cs.fold<double>(0, (a, t) => a + t.width + size * .08) / r;
  while (total() > math.pi * .88 && size > 22) { size -= 3; cs = chars(); }
  final span = total();
  var a = top ? -math.pi / 2 - span / 2 : math.pi / 2 + span / 2;
  for (final t in cs) {
    final step = (t.width + size * .08) / r;
    final mid = top ? a + step / 2 : a - step / 2;
    canvas.save();
    canvas.translate(ctr.dx + r * math.cos(mid), ctr.dy + r * math.sin(mid));
    canvas.rotate(top ? mid + math.pi / 2 : mid - math.pi / 2);
    t.paint(canvas, Offset(-t.width / 2, -t.height / 2));
    canvas.restore();
    a = top ? a + step : a - step;
  }
}

/// Photo of a real (paper) stamp → coloured ink on transparent background, cropped.
Future<Uint8List?> photoToStamp(String path) async {
  final small = await ImageProcessingService.instance.applyFilter(path, FilterMode.original, maxSide: 1400);
  final codec = await ui.instantiateImageCodec(await File(small).readAsBytes());
  final src = (await codec.getNextFrame()).image;
  final raw = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final w = src.width, h = src.height;
  final out = Uint8List(raw.length);
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = raw[i], g = raw[i + 1], b = raw[i + 2];
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      if (lum < 120 || (sat > .28 && lum < 225)) {
        out[i] = r; out[i + 1] = g; out[i + 2] = b;
        out[i + 3] = 235;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  final full = await _fromPixels(out, w, h);
  final cx = math.max(0, minX - 6), cy = math.max(0, minY - 6);
  final cw = math.min(w, maxX + 7) - cx, ch = math.min(h, maxY + 7) - cy;
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(full, Rect.fromLTWH(cx.toDouble(), cy.toDouble(), cw.toDouble(), ch.toDouble()),
      Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), Paint());
  final img = await rec.endRecording().toImage(cw, ch);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<ui.Image> _fromPixels(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

// ───────────────────────── saved stamps

class StampStore {
  static Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<List<File>> all() async {
    final f = (await _dir()).listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    f.sort((a, b) => b.path.compareTo(a.path));
    return f;
  }

  static Future<File> save(Uint8List png) async {
    final f = File('${(await _dir()).path}/stamp_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(png);
    return f;
  }
}

// ───────────────────────── picker screen

const _ready = <StampSpec>[
  StampSpec(middle: 'APPROVED', color: 0xFF2E7D32),
  StampSpec(middle: 'PAID', color: 0xFFC62828),
  StampSpec(middle: 'RECEIVED', color: 0xFF1565C0),
  StampSpec(middle: 'VERIFIED', color: 0xFF2E7D32),
  StampSpec(middle: 'ORIGINAL', color: 0xFF1565C0),
  StampSpec(middle: 'COPY', color: 0xFF212121),
  StampSpec(middle: 'ATTESTED', color: 0xFF1565C0),
  StampSpec(middle: 'CONFIDENTIAL', color: 0xFFC62828),
  StampSpec(middle: 'URGENT', color: 0xFFC62828),
  StampSpec(middle: 'CANCELLED', color: 0xFFC62828),
  StampSpec(middle: 'REJECTED', color: 0xFFC62828),
  StampSpec(middle: 'DRAFT', color: 0xFF616161),
];

/// Choose a stamp: your saved stamps, ready stamps, make a new one, or scan a paper stamp.
/// Pops the stamp PNG bytes.
class StampPickerScreen extends StatefulWidget {
  const StampPickerScreen({super.key});
  @override
  State<StampPickerScreen> createState() => _StampPickerScreenState();
}

class _StampPickerScreenState extends State<StampPickerScreen> {
  List<File> _mine = [];
  bool _date = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await StampStore.all();
    if (mounted) setState(() => _mine = m);
  }

  Future<void> _create() async {
    final png = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const StampDesignerScreen()));
    if (png == null) return;
    await StampStore.save(png);
    if (mounted) Navigator.pop(context, png);
  }

  Future<void> _scan() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 95);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final png = await photoToStamp(x.path);
      if (png == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No stamp found — put the stamp on white paper')));
        return;
      }
      await StampStore.save(png);
      if (mounted) Navigator.pop(context, png);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(Widget child, VoidCallback onTap, {VoidCallback? onLong}) => InkWell(
        onTap: onTap,
        onLongPress: onLong,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE0E4E4)), borderRadius: BorderRadius.circular(6)),
          child: Center(child: child),
        ),
      );

  Widget _head(AppPalette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(t, style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const grid = SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.6);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F4),
      appBar: AppBar(backgroundColor: p.appBar, title: const Text('Stamp')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 6, 0),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.accent, minimumSize: const Size.fromHeight(48)),
                  onPressed: _create, icon: const Icon(Icons.add), label: const Text('Create Stamp'),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 12, 0),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: p.accent, minimumSize: const Size.fromHeight(48)),
                  onPressed: _scan, icon: const Icon(Icons.photo_camera), label: const Text('Scan Stamp'),
                ),
              ),
            ),
          ]),
          if (_mine.isNotEmpty) ...[
            _head(p, 'My Stamps (long-press to delete)'),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12), gridDelegate: grid, itemCount: _mine.length,
              itemBuilder: (_, i) => _tile(
                Image.file(_mine[i], fit: BoxFit.contain),
                () async { final b = await _mine[i].readAsBytes(); if (mounted) Navigator.pop(context, b); },
                onLong: () async {
                  if (await confirm(context, 'Delete stamp?', 'This saved stamp will be removed.')) {
                    await _mine[i].delete();
                    _load();
                  }
                },
              ),
            ),
          ],
          _head(p, 'Ready Stamps'),
          SwitchListTile(
            dense: true, activeColor: p.accent,
            title: const Text("Add today's date"), value: _date, onChanged: (v) => setState(() => _date = v),
          ),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12), gridDelegate: grid, itemCount: _ready.length,
            itemBuilder: (_, i) {
              final s = _ready[i].copyWith(date: _date);
              return FutureBuilder<Uint8List>(
                key: ValueKey(s.key),
                future: renderStamp(s),
                builder: (_, snap) => _tile(
                  snap.hasData ? Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true) : const SizedBox(),
                  () { if (snap.hasData) Navigator.pop(context, snap.data); },
                ),
              );
            },
          ),
        ]),
        if (_busy) Positioned.fill(child: Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: p.accent)))),
      ]),
    );
  }
}

// ───────────────────────── designer

/// Make your own stamp: company name round seal or rectangle, colour, date.
class StampDesignerScreen extends StatefulWidget {
  const StampDesignerScreen({super.key});
  @override
  State<StampDesignerScreen> createState() => _StampDesignerScreenState();
}

class _StampDesignerScreenState extends State<StampDesignerScreen> {
  StampSpec _s = const StampSpec(top: 'COMPANY NAME', middle: 'APPROVED', bottom: 'CITY', shape: 'round');
  late final _top = TextEditingController(text: _s.top);
  late final _mid = TextEditingController(text: _s.middle);
  late final _bot = TextEditingController(text: _s.bottom);
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    _redraw();
  }

  Future<void> _redraw() async {
    final b = await renderStamp(_s);
    if (mounted) setState(() => _png = b);
  }

  void _set(StampSpec s) { _s = s; _redraw(); }

  Widget _field(TextEditingController c, String label, void Function(String) on) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TextField(
          controller: c, textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          onChanged: on,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final round = _s.shape == 'round';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: p.appBar,
        title: const Text('Create Stamp'),
        actions: [IconButton(icon: const Icon(Icons.check), tooltip: 'Save', onPressed: _png == null ? null : () => Navigator.pop(context, _png))],
      ),
      body: ListView(children: [
        Container(
          height: 220, margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF7F7F2), border: Border.all(color: const Color(0xFFE0E4E4))),
          padding: const EdgeInsets.all(12),
          child: _png == null ? const SizedBox() : Image.memory(_png!, fit: BoxFit.contain, gaplessPlayback: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'round', icon: Icon(Icons.circle_outlined), label: Text('Round')),
              ButtonSegment(value: 'rect', icon: Icon(Icons.crop_landscape), label: Text('Rectangle')),
            ],
            selected: {_s.shape},
            onSelectionChanged: (v) => _set(_s.copyWith(shape: v.first)),
          ),
        ),
        const SizedBox(height: 8),
        _field(_top, round ? 'Top text (company name)' : 'Top line', (v) => _set(_s.copyWith(top: v))),
        _field(_mid, round ? 'Centre text' : 'Main text', (v) => _set(_s.copyWith(middle: v))),
        _field(_bot, round ? 'Bottom text (city / phone)' : 'Bottom line', (v) => _set(_s.copyWith(bottom: v))),
        CheckboxListTile(
          activeColor: p.accent, title: const Text("Add today's date"), value: _s.date,
          onChanged: (v) => _set(_s.copyWith(date: v ?? false)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Row(children: [
            const Text('Colour', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 16),
            for (final c in stampColors)
              GestureDetector(
                onTap: () => _set(_s.copyWith(color: c.toARGB32())),
                child: Container(
                  width: 36, height: 36, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(color: _s.color == c.toARGB32() ? Colors.black : Colors.transparent, width: 3),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
