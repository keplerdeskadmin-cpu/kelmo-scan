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
import '../theme/app_themes.dart';
import 'quad_painter.dart';

/// Image + draggable 4-corner crop frame (manual adjustment pins).
class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.imagePath,
    required this.aspect,
    required this.corners,
    required this.onChanged,
  });
  final String imagePath;
  final double aspect; // image width / height
  final List<Offset> corners; // normalised TL,TR,BR,BL
  final ValueChanged<List<Offset>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: Image.file(File(imagePath), fit: BoxFit.fill, cacheWidth: 1600)),
          Positioned.fill(
              child: CustomPaint(painter: QuadPainter(corners, p.cropLine, p.cropHandle, handles: false))),
          for (int i = 0; i < 4; i++)
            Positioned(
              left: corners[i].dx * w - 18,
              top: corners[i].dy * h - 18,
              child: GestureDetector(
                onPanUpdate: (d) {
                  final n = List<Offset>.from(corners);
                  n[i] = Offset(
                    (corners[i].dx + d.delta.dx / w).clamp(0.0, 1.0).toDouble(),
                    (corners[i].dy + d.delta.dy / h).clamp(0.0, 1.0).toDouble(),
                  );
                  onChanged(n);
                },
                child: Container(
                  width: 36, height: 36, color: Colors.transparent, // big touch target
                  alignment: Alignment.center,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: p.cropHandle, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}
