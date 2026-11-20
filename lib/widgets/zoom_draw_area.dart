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

/// Drawing surface with two-finger zoom / pan.
/// One finger → draw callbacks (positions normalised 0..1 on the page).
/// Two fingers → [onTwoStart] may claim the gesture (e.g. turn a stamp); otherwise the page zooms.
class ZoomDrawArea extends StatefulWidget {
  const ZoomDrawArea({
    super.key,
    required this.aspect,
    required this.builder,
    this.onOneStart,
    this.onOneUpdate,
    this.onOneEnd,
    this.onOneCancel,
    this.onTwoStart,
    this.onTwoUpdate,
    this.onTap,
  });
  final double aspect;
  final Widget Function(Size size) builder;
  final void Function(Offset n, Size size)? onOneStart, onOneUpdate;
  final VoidCallback? onOneEnd;
  final VoidCallback? onOneCancel; // a second finger landed: drop the stroke just started
  final bool Function(Offset n, Size size)? onTwoStart;
  final void Function(Offset n, double scale, double rotation)? onTwoUpdate;
  final void Function(Offset n, Size size)? onTap;
  @override
  State<ZoomDrawArea> createState() => _ZoomDrawAreaState();
}

class _ZoomDrawAreaState extends State<ZoomDrawArea> {
  double _zoom = 1, _z0 = 1;
  Offset _pan = Offset.zero, _p0 = Offset.zero, _f0 = Offset.zero;
  int _mode = 0; // 0 none, 1 draw, 2 caller two-finger, 3 zoom
  bool _blockOne = false; // after a two-finger gesture, wait until all fingers are up

  Offset _norm(Offset local, Size s) {
    final c = (local - _pan) / _zoom;
    return Offset((c.dx / s.width).clamp(0.0, 1.0), (c.dy / s.height).clamp(0.0, 1.0));
  }

  Offset _clampPan(Offset pan, Size s) => Offset(
        pan.dx.clamp(s.width * (1 - _zoom), 0.0).toDouble(),
        pan.dy.clamp(s.height * (1 - _zoom), 0.0).toDouble(),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Center(
        child: AspectRatio(
          aspectRatio: widget.aspect,
          child: LayoutBuilder(builder: (_, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              onTapUp: widget.onTap == null ? null : (d) => widget.onTap!(_norm(d.localPosition, size), size),
              onDoubleTap: () => setState(() { _zoom = _zoom > 1 ? 1 : 2.5; _pan = _zoom == 1 ? Offset.zero : _clampPan(-Offset(size.width, size.height) * .75, size); }),
              onScaleStart: (d) {
                if (d.pointerCount >= 2) {
                  _blockOne = true;
                  final n = _norm(d.localFocalPoint, size);
                  if (widget.onTwoStart?.call(n, size) ?? false) {
                    _mode = 2;
                  } else {
                    _mode = 3;
                    _z0 = _zoom;
                    _p0 = _pan;
                    _f0 = d.localFocalPoint;
                  }
                } else if (_blockOne) {
                  _mode = 0;
                } else {
                  _mode = 1;
                  widget.onOneStart?.call(_norm(d.localFocalPoint, size), size);
                }
              },
              onScaleUpdate: (d) {
                switch (_mode) {
                  case 1:
                    if (d.pointerCount == 1) widget.onOneUpdate?.call(_norm(d.localFocalPoint, size), size);
                  case 2:
                    widget.onTwoUpdate?.call(_norm(d.localFocalPoint, size), d.scale, d.rotation);
                  case 3:
                    setState(() {
                      _zoom = (_z0 * d.scale).clamp(1.0, 6.0).toDouble();
                      final content = (_f0 - _p0) / _z0; // page point under the fingers
                      _pan = _clampPan(d.localFocalPoint - content * _zoom, size);
                    });
                }
              },
              onScaleEnd: (d) {
                if (_mode == 1) {
                  if (d.pointerCount >= 2) {
                    _blockOne = true;
                    (widget.onOneCancel ?? widget.onOneEnd)?.call();
                  } else {
                    widget.onOneEnd?.call();
                  }
                }
                if (d.pointerCount == 0) _blockOne = false;
                _mode = 0;
              },
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_pan.dx, _pan.dy)
                    ..scale(_zoom, _zoom),
                  child: widget.builder(size),
                ),
              ),
            );
          }),
        ),
      ),
      if (_zoom > 1)
        Positioned(
          right: 8, top: 8,
          child: Material(
            color: Colors.black54, shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Fit page',
              icon: const Icon(Icons.zoom_out_map, color: Colors.white),
              onPressed: () => setState(() { _zoom = 1; _pan = Offset.zero; }),
            ),
          ),
        ),
    ]);
  }
}
