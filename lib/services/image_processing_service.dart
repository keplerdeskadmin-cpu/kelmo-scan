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
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/services.dart';
import '../models/scan_document.dart';
import 'package:path_provider/path_provider.dart';

/// Filters exposed in the UI. [native] is the key understood by Kotlin.
enum FilterMode {
  original('original', 'Original'),
  auto('auto', 'Auto'),
  photo('photo', 'Photo'),
  magicColor('magic', 'Magic Color'),
  bw('bw', 'B&W'),
  grayscale('grayscale', 'Grayscale');

  const FilterMode(this.native, this.label);
  final String native, label;
  static FilterMode fromNative(String k) =>
      values.firstWhere((m) => m.native == k, orElse: () => FilterMode.auto);
}

/// Dart side of the native OpenCV bridge (MethodChannel "doc_scanner/cv").
///
/// Design rules:
///  * Large images travel as FILE PATHS, never as byte arrays → no 10-30 MB
///    copies through the platform channel.
///  * Only live-preview frames (Y plane, ~1 MB) are sent as bytes.
///  * Corners are always normalised 0..1 (TL, TR, BR, BL) so they are
///    resolution independent.
///  * Kotlin runs everything on a background thread; the UI isolate never blocks.
class ImageProcessingService {
  ImageProcessingService._();
  static final instance = ImageProcessingService._();
  static const _ch = MethodChannel('doc_scanner/cv');

  /// Real-time detection on a camera frame's luminance plane.
  Future<List<Offset>?> detectFrame({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int rowStride,
    required int rotation,
  }) async =>
      _quad(await _ch.invokeMethod('detectFrame', {
        'bytes': yPlane, 'width': width, 'height': height,
        'rowStride': rowStride, 'rotation': rotation,
      }));

  /// High-quality detection on a captured photo.
  Future<List<Offset>?> detectCorners(String path) async =>
      _quad(await _ch.invokeMethod('detectCorners', {'path': path}));

  /// Perspective-flattens [path] using the 4 [corners] (A4/Letter snapping).
  Future<String> warp(String path, List<Offset> corners) async {
    final out = await _tmp('flat');
    await _ch.invokeMethod('warp', {
      'path': path, 'out': out,
      'corners': [for (final c in corners) ...[c.dx, c.dy]],
    });
    return out;
  }

  /// Runs a filter. [maxSide] > 0 downsamples first (thumbnails / previews).
  Future<String> applyFilter(String path, FilterMode mode, {int maxSide = 0}) async {
    final out = await _tmp('f_${mode.native}');
    await _ch.invokeMethod('applyFilter',
        {'path': path, 'out': out, 'mode': mode.native, 'maxSide': maxSide});
    return out;
  }

  Future<String> rotate90(String path) async {
    final out = await _tmp('rot');
    await _ch.invokeMethod('rotate', {'path': path, 'out': out});
    return out;
  }

  /// Re-encodes [path] for sharing (long side <= [maxSide], JPEG [quality] 1..100).
  Future<String> shrink(String path, int maxSide, int quality) async {
    final out = await _tmp('share');
    await _ch.invokeMethod('shrink', {'path': path, 'out': out, 'maxSide': maxSide, 'quality': quality});
    return out;
  }

  /// Bakes redact / blur / highlight rectangles into the image. Each mark = [type, x0, y0, x1, y1] (0..1).
  Future<String> applyMarks(String path, List<List<double>> marks) async {
    final out = await _tmp('redact');
    await _ch.invokeMethod('applyMarks', {'path': path, 'out': out, 'marks': [for (final m in marks) ...m]});
    return out;
  }

  /// Puts the processed front + back images on one white A4 page (native, 300 dpi).
  Future<ScannedPage> composeIdCard(ScannedPage front, ScannedPage back) async {
    final out = await _tmp('id');
    await _ch.invokeMethod('composeId', {'front': front.finalPath, 'back': back.finalPath, 'out': out});
    final thumb = await applyFilter(out, FilterMode.original, maxSide: 360);
    return ScannedPage(
      origPath: out, finalPath: out, thumbPath: thumb, filter: 'original',
      corners: const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
    );
  }

  List<Offset>? _quad(dynamic r) {
    if (r == null) return null;
    final l = (r as List).map((e) => (e as num).toDouble()).toList();
    if (l.length < 8) return null;
    return List.generate(4, (i) => Offset(l[i * 2], l[i * 2 + 1]));
  }

  Future<String> _tmp(String tag) async {
    final d = await getTemporaryDirectory();
    return '${d.path}/${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg';
  }

  Future<void> deleteQuietly(String? p) async {
    if (p == null) return;
    try { await File(p).delete(); } catch (_) {}
  }
}
