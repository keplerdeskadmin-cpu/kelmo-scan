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

import 'dart:ui' show Offset;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scan_document.dart';
import 'app_settings.dart';
import 'image_processing_service.dart';

/// Import PDF / images without the camera, blank pages, image adjust, shutter sound.
class ImportService {
  static const _ch = MethodChannel('doc_scanner/cv');
  static const _full = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

  static Future<ScannedPage> pageFromImage(String path) async {
    final svc = ImageProcessingService.instance;
    final img = await svc.shrink(path, 100000, AppSettings.instance.jpegQuality); // normalised JPEG copy
    final thumb = await svc.applyFilter(img, FilterMode.original, maxSide: 360);
    return ScannedPage(origPath: img, finalPath: img, thumbPath: thumb, corners: _full, filter: 'original');
  }

  static Future<List<ScannedPage>> pagesFromImages(List<String> paths) async =>
      [for (final p in paths) await pageFromImage(p)];

  /// Lets the user pick a PDF and returns each page as a JPEG (null = cancelled).
  static Future<List<String>?> pickPdfPages() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = r?.files.single.path;
    if (path == null) return null;
    return pdfFilePages(path);
  }

  /// Every page of a PDF file as a JPEG.
  static Future<List<String>> pdfFilePages(String path) async {
    final dir = await getTemporaryDirectory();
    final out = await _ch.invokeListMethod<String>(
        'renderPdf', {'path': path, 'outDir': '${dir.path}/pdf_import_${DateTime.now().millisecondsSinceEpoch}', 'maxSide': 2400});
    return out ?? [];
  }

  /// Images from files (Import images) — no border step, like Clear Scanner's import.
  static Future<List<String>> pickImages() async {
    final f = await ImagePicker().pickMultiImage();
    return [for (final x in f) x.path];
  }

  static Future<String> blankPage() async {
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/blank_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _ch.invokeMethod('blankPage', {'out': out, 'width': 2480, 'height': 3508});
    return out;
  }

  /// brightness -100..100, contrast 0.5..2.0
  static Future<String> adjust(String path, double brightness, double contrast) async {
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/adj_${DateTime.now().microsecondsSinceEpoch}.jpg';
    // contrast around mid-grey: out = c*in + b + 128*(1-c)
    await _ch.invokeMethod('adjust', {'path': path, 'out': out, 'brightness': brightness + 128 * (1 - contrast), 'contrast': contrast});
    return out;
  }

  static Future<void> shutter() async {
    if (!AppSettings.instance.shutterSound) return;
    try { await _ch.invokeMethod('shutter'); } catch (_) {}
  }
}
