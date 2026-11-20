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

import 'package:flutter/material.dart';

/// Draws the detected document quad (normalised points) over the camera preview.
class QuadPainter extends CustomPainter {
  QuadPainter(this.quad, this.line, this.handle, {this.handles = true});
  final List<Offset>? quad;
  final Color line, handle;
  final bool handles;

  @override
  void paint(Canvas canvas, Size s) {
    final q = quad;
    if (q == null || q.length < 4) return;
    final pts = [for (final o in q) Offset(o.dx * s.width, o.dy * s.height)];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = line.withAlpha(34));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
    if (handles) {
      for (final p in pts) {
        canvas.drawCircle(p, 8, Paint()..color = handle);
        canvas.drawCircle(p, 8, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(QuadPainter old) => old.quad != quad || old.line != line;
}
