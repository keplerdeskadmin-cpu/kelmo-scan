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

const kBorderGreen = Color(0xFF2EE33A);

/// Image with a green 4-corner border: corner rings, edge squares, and a
/// round magnifier (with cross-hair) while a handle is being dragged.
class BorderAdjustOverlay extends StatefulWidget {
  const BorderAdjustOverlay({
    super.key,
    required this.imagePath,
    required this.aspect,
    required this.corners,
    required this.onChanged,
  });
  final String imagePath;
  final double aspect; // image width / height
  final List<Offset> corners; // normalised TL, TR, BR, BL
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<BorderAdjustOverlay> createState() => _BorderAdjustOverlayState();
}

class _BorderAdjustOverlayState extends State<BorderAdjustOverlay> {
  int? _active; // 0..3 corners, 4..7 edges (TL-TR, TR-BR, BR-BL, BL-TL)
  Offset? _focus; // normalised point shown in the magnifier

  static Offset _clamp(Offset o) => Offset(o.dx.clamp(0.0, 1.0).toDouble(), o.dy.clamp(0.0, 1.0).toDouble());

  void _drag(int i, Offset deltaPx, double w, double h) {
    final d = Offset(deltaPx.dx / w, deltaPx.dy / h);
    final n = List<Offset>.from(widget.corners);
    if (i < 4) {
      n[i] = _clamp(n[i] + d);
      _focus = n[i];
    } else {
      final a = i - 4, b = (i - 3) % 4;
      n[a] = _clamp(n[a] + d);
      n[b] = _clamp(n[b] + d);
      _focus = Offset((n[a].dx + n[b].dx) / 2, (n[a].dy + n[b].dy) / 2);
    }
    widget.onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.corners;
    return AspectRatio(
      aspectRatio: widget.aspect,
      child: LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final handles = <Widget>[];
        for (int i = 0; i < 8; i++) {
          final Offset pt = i < 4
              ? c[i]
              : Offset((c[i - 4].dx + c[(i - 3) % 4].dx) / 2, (c[i - 4].dy + c[(i - 3) % 4].dy) / 2);
          handles.add(Positioned(
            left: pt.dx * w - 24,
            top: pt.dy * h - 24,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => setState(() { _active = i; _focus = pt; }),
              onPanUpdate: (d) => setState(() => _drag(i, d.delta, w, h)),
              onPanEnd: (_) => setState(() { _active = null; _focus = null; }),
              child: SizedBox(
                width: 48, height: 48,
                child: Center(
                  child: i < 4
                      ? Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _active == i ? kBorderGreen.withAlpha(90) : Colors.transparent,
                            border: Border.all(color: kBorderGreen, width: 2.5),
                          ),
                        )
                      : Container(width: 13, height: 13, color: kBorderGreen),
                ),
              ),
            ),
          ));
        }
        final f = _focus;
        // Magnifier sits in the corner away from the finger.
        const r = 62.0, zoom = 2.4;
        final magLeft = f != null && f.dx < .5 ? w - 2 * r - 6 : 6.0;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 1800)),
          Positioned.fill(child: CustomPaint(painter: _BorderPainter(c))),
          ...handles,
          if (f != null)
            Positioned(
              left: magLeft,
              top: 6,
              child: Container(
                width: 2 * r, height: 2 * r,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBorderGreen, width: 3)),
                child: ClipOval(
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned(
                      left: r - f.dx * w * zoom,
                      top: r - f.dy * h * zoom,
                      width: w * zoom,
                      height: h * zoom,
                      child: Stack(children: [
                        Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 2400)),
                        Positioned.fill(child: CustomPaint(painter: _BorderPainter(c, stroke: 3 * zoom / 2))),
                      ]),
                    ),
                    Positioned(left: r - 1, top: 0, bottom: 0, child: Container(width: 2, color: kBorderGreen)),
                    Positioned(top: r - 1, left: 0, right: 0, child: Container(height: 2, color: kBorderGreen)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

class _BorderPainter extends CustomPainter {
  _BorderPainter(this.q, {this.stroke = 2.5});
  final List<Offset> q;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    if (q.length < 4) return;
    final pts = [for (final o in q) Offset(o.dx * s.width, o.dy * s.height)];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = kBorderGreen.withAlpha(28));
    canvas.drawPath(
        path,
        Paint()
          ..color = kBorderGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_BorderPainter old) => old.q != q || old.stroke != stroke;
}
