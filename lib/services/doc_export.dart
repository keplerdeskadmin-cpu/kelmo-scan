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
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scan_document.dart';
import 'app_settings.dart';
import 'image_processing_service.dart';
import 'pdf_exporter.dart';

/// File size presets: long side in pixels, JPEG quality, and a rough size factor for the estimate.
enum ExportSize {
  small('Small', 1200, 60, .28),
  medium('Medium', 1800, 75, .5),
  large('Large', 2600, 85, .8),
  original('Original', 0, 92, 1.0);

  const ExportSize(this.label, this.maxSide, this.quality, this.factor);
  final String label;
  final int maxSide, quality;
  final double factor;
}

String bytesLabel(num b) =>
    b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';

/// PDF / JPG export, gallery + Downloads saving, e-mail and printing for a set of pages.
class DocExport {
  static const _ch = MethodChannel('doc_scanner/cv');

  static String safeName(String n) {
    final s = n.trim().replaceAll(RegExp(r'[^\w\- ]+'), '_');
    return s.isEmpty ? 'Kelmo Scan' : s;
  }

  static int sourceBytes(List<ScanPage> pages) {
    var sum = 0;
    for (final p in pages) {
      try { sum += File(p.imagePath).lengthSync(); } catch (_) {}
    }
    return sum;
  }

  static String estimate(List<ScanPage> pages, ExportSize s) => '${s.label} (~${bytesLabel(sourceBytes(pages) * s.factor)})';

  static Future<List<String>> images(List<ScanPage> pages, ExportSize size) async {
    final svc = ImageProcessingService.instance;
    return [
      for (final p in pages)
        size == ExportSize.original ? p.imagePath : await svc.shrink(p.imagePath, size.maxSide, size.quality)
    ];
  }

  static Future<String> pdf(List<ScanPage> pages, String name,
          {ExportSize size = ExportSize.medium, String watermark = '', PdfSize? page}) async =>
      PdfExporter.save(await images(pages, size), safeName(name),
          size: page ?? AppSettings.instance.pdfSize, watermark: watermark);

  static Future<void> sharePdf(List<ScanPage> pages, String name,
      {ExportSize size = ExportSize.medium, String watermark = '', PdfSize? page}) async {
    final path = await pdf(pages, name, size: size, watermark: watermark, page: page);
    await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')], subject: name);
  }

  static Future<void> shareJpgs(List<ScanPage> pages, String name, {ExportSize size = ExportSize.medium}) async {
    final imgs = await images(pages, size);
    final n = safeName(name);
    await Share.shareXFiles([
      for (var i = 0; i < imgs.length; i++)
        XFile(imgs[i], name: imgs.length == 1 ? '$n.jpg' : '${n}_${i + 1}.jpg', mimeType: 'image/jpeg')
    ], subject: name);
  }

  /// Opens the share sheet with the PDF attached and the subject filled in — pick Gmail / Outlook.
  static Future<void> email(List<ScanPage> pages, String name, {String watermark = ''}) async {
    final path = await pdf(pages, name, watermark: watermark);
    await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')], subject: name, text: 'Scanned with Kelmo Scan');
  }

  static Future<void> printPdf(List<ScanPage> pages, String name, {String watermark = ''}) async {
    final path = await pdf(pages, name, size: ExportSize.large, watermark: watermark);
    await _ch.invokeMethod('printPdf', {'path': path, 'name': safeName(name)});
  }

  /// Saves every page as a JPG into Pictures/Kelmo Scan. Returns the folder shown to the user.
  static Future<String> toGallery(List<ScanPage> pages, String name) async {
    final n = safeName(name);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    String where = '';
    for (var i = 0; i < pages.length; i++) {
      where = await _ch.invokeMethod<String>('saveToGallery', {
            'path': pages[i].imagePath,
            'name': pages.length == 1 ? '${n}_$stamp.jpg' : '${n}_${stamp}_${i + 1}.jpg',
            'mime': 'image/jpeg',
          }) ??
          '';
    }
    return where.contains('/') ? where.substring(0, where.lastIndexOf('/')) : 'Pictures/Kelmo Scan';
  }

  /// Saves the PDF into Download/Kelmo Scan. Returns the full visible path.
  static Future<String> toStorage(List<ScanPage> pages, String name,
      {ExportSize size = ExportSize.medium, String watermark = ''}) async {
    final path = await pdf(pages, name, size: size, watermark: watermark);
    final n = '${safeName(name)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return await _ch.invokeMethod<String>('saveToDownloads', {'path': path, 'name': n, 'mime': 'application/pdf'}) ??
        'Download/Kelmo Scan/$n';
  }
}
