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
import 'document_repository.dart';
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

/// PDF layout for a document: per-document "PDF Settings", else the defaults from Settings.
class PdfOpts {
  PdfOpts(this.page, this.orientation, this.fill, this.quality);
  PdfSize page;
  String orientation; // auto | portrait | landscape
  bool fill; // true = fill the entire page, false = fit width or height
  ExportSize quality;

  static ExportSize qualityFor(String r) =>
      const {'low': ExportSize.small, 'medium': ExportSize.medium, 'high': ExportSize.large, 'original': ExportSize.original}[r] ??
      ExportSize.medium;

  static PdfOpts defaults() {
    final s = AppSettings.instance;
    return PdfOpts(s.pdfSize, s.pdfOrientation, s.pdfScale == 'fill', qualityFor(s.pdfResolution));
  }

  static Future<PdfOpts> forDoc(int? docId) async {
    final o = defaults();
    if (docId == null) return o;
    final m = await DocumentRepository.instance.pdfSettings(docId);
    if (m == null) return o;
    o.page = PdfSize.values.firstWhere((x) => x.name == m['page'], orElse: () => o.page);
    o.orientation = (m['orientation'] as String?) ?? o.orientation;
    o.fill = (m['scale'] as String?) == null ? o.fill : m['scale'] == 'fill';
    o.quality = m['resolution'] == null ? o.quality : qualityFor(m['resolution'] as String);
    return o;
  }

  Map<String, dynamic> toMap() => {
        'page': page.name, 'orientation': orientation, 'scale': fill ? 'fill' : 'fit',
        'resolution': const {ExportSize.small: 'low', ExportSize.medium: 'medium', ExportSize.large: 'high', ExportSize.original: 'original'}[quality],
      };
}

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
      {ExportSize? size, String watermark = '', PdfSize? page, String password = ''}) async {
    final o = await PdfOpts.forDoc(pages.isEmpty ? null : pages.first.docId);
    final path = await PdfExporter.save(await images(pages, size ?? o.quality), safeName(name),
        size: page ?? o.page, watermark: watermark, orientation: o.orientation, fill: o.fill);
    if (password.isEmpty) return path;
    // AES password protection (opens only with the password)
    final out = path.replaceAll(RegExp(r'\.pdf$'), '') + '_locked.pdf';
    await _ch.invokeMethod('protectPdf', {'path': path, 'out': out, 'password': password});
    final f = File(out);
    await f.rename(path);
    return path;
  }

  static Future<void> sharePdf(List<ScanPage> pages, String name,
      {ExportSize? size, String watermark = '', PdfSize? page, String password = ''}) async {
    final path = await pdf(pages, name, size: size, watermark: watermark, page: page, password: password);
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

  /// E-mail with the PDF attached; uses the Default Email (To / Subject) from Settings.
  static Future<void> email(List<ScanPage> pages, String name, {String watermark = '', String password = ''}) async {
    final path = await pdf(pages, name, watermark: watermark, password: password);
    final s = AppSettings.instance;
    try {
      await _ch.invokeMethod('emailFile', {
        'path': path, 'mime': 'application/pdf', 'to': s.emailTo,
        'subject': s.emailSubject.isEmpty ? name : s.emailSubject, 'body': 'Document created by Kelmo Scan',
      });
    } catch (_) {
      await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')], subject: name, text: 'Document created by Kelmo Scan');
    }
  }

  static Future<void> printPdf(List<ScanPage> pages, String name, {String watermark = ''}) async {
    final path = await pdf(pages, name, watermark: watermark);
    await _ch.invokeMethod('printPdf', {'path': path, 'name': safeName(name)});
  }

  /// Saves every page as a JPG into Pictures/Kelmo Scan. Returns the folder shown to the user.
  static Future<String> toGallery(List<ScanPage> pages, String name) =>
      imagesToGallery([for (final p in pages) p.imagePath], name);

  /// File name per the "Auto-save file name format" setting (Page ID / date & time).
  static String galleryName(String name, int index) {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    final dt = '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}${t(n.second)}';
    final id = '${safeName(name)}_${(index + 1).toString().padLeft(2, '0')}';
    return switch (AppSettings.instance.galleryNameFormat) {
      'id' => '$id.jpg',
      'dt_id' => '${dt}_$id.jpg',
      _ => '${id}_$dt.jpg',
    };
  }

  static Future<String> imagesToGallery(List<String> paths, String name) async {
    String where = '';
    for (var i = 0; i < paths.length; i++) {
      where = await _ch.invokeMethod<String>('saveToGallery', {
            'path': paths[i], 'name': galleryName(name, i), 'mime': 'image/jpeg',
          }) ??
          '';
    }
    return where.contains('/') ? where.substring(0, where.lastIndexOf('/')) : 'Pictures/Kelmo Scan';
  }

  /// Saves the PDF into Download/Kelmo Scan. Returns the full visible path.
  static Future<String> toStorage(List<ScanPage> pages, String name,
      {ExportSize? size, String watermark = '', String password = ''}) async {
    final path = await pdf(pages, name, size: size, watermark: watermark, password: password);
    final n = '${safeName(name)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return await _ch.invokeMethod<String>('saveToDownloads', {'path': path, 'name': n, 'mime': 'application/pdf'}) ??
        'Download/Kelmo Scan/$n';
  }
}
