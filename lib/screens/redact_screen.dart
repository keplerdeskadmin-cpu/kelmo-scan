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
import '../services/image_processing_service.dart';
import '../theme/app_themes.dart';
import '../widgets/dialogs.dart';

class _Mark {
  _Mark(this.type, this.rect);
  final int type; // 0 redact, 1 blur, 2 highlight
  final Rect rect; // normalised 0..1
}

/// Draw rectangles to redact / blur / highlight. "Save safely" bakes them into the pixels natively
/// and pops the new image path (null = cancelled).
class RedactScreen extends StatefulWidget {
  const RedactScreen({super.key, required this.imagePath});
  final String imagePath;
  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  double _aspect = .75;
  int _tool = 0;
  final List<_Mark> _marks = [];
  Offset? _a, _b;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FileImage(File(widget.imagePath)).resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) setState(() => _aspect = info.image.width / info.image.height);
      }),
    );
  }

  Future<void> _save() async {
    if (_marks.isEmpty) { Navigator.pop(context); return; }
    final ok = await confirm(context, 'Apply permanently?',
        'Redacted and blurred areas cannot be recovered, and the original photo of this page is replaced.',
        yes: 'Apply');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final out = await ImageProcessingService.instance.applyMarks(widget.imagePath, [
        for (final m in _marks) [m.type.toDouble(), m.rect.left, m.rect.top, m.rect.right, m.rect.bottom]
      ]);
      if (mounted) Navigator.pop(context, out);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Widget _toolBtn(AppPalette p, int i, IconData icon, String label) {
    final on = _tool == i;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _tool = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? p.accent.withAlpha(35) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? p.accent : p.outline),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: p.accent),
            Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.text)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: const Text('Protect sensitive info')),
      body: Column(children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: p.surfaceAlt,
            padding: const EdgeInsets.all(12),
            child: Center(
              child: AspectRatio(
                aspectRatio: _aspect,
                child: LayoutBuilder(builder: (_, box) {
                  final w = box.maxWidth, h = box.maxHeight;
                  Offset norm(Offset o) => Offset((o.dx / w).clamp(0.0, 1.0).toDouble(), (o.dy / h).clamp(0.0, 1.0).toDouble());
                  return GestureDetector(
                    onPanStart: (d) => setState(() { _a = norm(d.localPosition); _b = _a; }),
                    onPanUpdate: (d) => setState(() => _b = norm(d.localPosition)),
                    onPanEnd: (_) {
                      if (_a != null && _b != null) {
                        final r = Rect.fromPoints(_a!, _b!);
                        if (r.width > 0.004 && r.height > 0.003) _marks.add(_Mark(_tool, r));
                      }
                      setState(() { _a = null; _b = null; });
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 1800),
                      CustomPaint(painter: _MarksPainter(_marks, _a == null || _b == null ? null : Rect.fromPoints(_a!, _b!), _tool)),
                    ]),
                  );
                }),
              ),
            ),
          ),
        ),
        Container(
          color: p.background,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                _toolBtn(p, 0, Icons.hide_source_rounded, 'Redact'),
                const SizedBox(width: 8),
                _toolBtn(p, 1, Icons.blur_on_rounded, 'Blur'),
                const SizedBox(width: 8),
                _toolBtn(p, 2, Icons.border_color_rounded, 'Highlight'),
                const SizedBox(width: 8),
                _toolBtn(p, 3, Icons.cleaning_services_rounded, 'Whiteout'),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _marks.isEmpty ? null : () => setState(() => _marks.removeLast()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.outline)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.undo_rounded, color: _marks.isEmpty ? p.textMuted : p.accent),
                        Text('Undo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.accent.withAlpha(24), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.shield_outlined, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Redactions are permanent after saving. Drag on the page to mark an area.', style: TextStyle(color: p.text, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 10),
              _busy
                  ? SizedBox(height: 52, child: Center(child: CircularProgressIndicator(color: p.accent)))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(52)),
                      onPressed: _save,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Save safely'),
                    ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.marks, this.current, this.tool);
  final List<_Mark> marks;
  final Rect? current;
  final int tool;

  Rect _px(Rect r, Size s) => Rect.fromLTRB(r.left * s.width, r.top * s.height, r.right * s.width, r.bottom * s.height);

  @override
  void paint(Canvas c, Size s) {
    for (final m in marks) {
      final paint = Paint()
        ..color = m.type == 0 ? Colors.black : (m.type == 1 ? const Color(0xCC8A94A6) : (m.type == 3 ? Colors.white : const Color(0x88FFEB3B)));
      c.drawRect(_px(m.rect, s), paint);
    }
    final cur = current;
    if (cur != null) {
      c.drawRect(
        _px(cur, s),
        Paint()
          ..color = tool == 0 ? Colors.black : (tool == 1 ? Colors.blueGrey : (tool == 3 ? Colors.grey : Colors.amber))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}
