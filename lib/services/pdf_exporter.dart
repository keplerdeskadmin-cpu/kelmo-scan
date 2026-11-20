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
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

enum PdfSize {
  a4('A4', PdfPageFormat.a4),
  letter('Letter', PdfPageFormat.letter),
  legal('Legal', PdfPageFormat.legal);

  const PdfSize(this.label, this.format);
  final String label;
  final PdfPageFormat format;
}

/// Runs in a background isolate so big scans never freeze the UI.
Future<Uint8List> _buildPdf(List<Object> a) async {
  final paths = (a[0] as List).cast<String>();
  final fmt = PdfPageFormat(a[1] as double, a[2] as double);
  final mark = a.length > 3 ? a[3] as String : '';
  final doc = pw.Document();
  for (final p in paths) {
    final img = pw.MemoryImage(File(p).readAsBytesSync());
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(alignment: pw.Alignment.center, children: [
        pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
        if (mark.isNotEmpty)
          pw.Transform.rotate(
            angle: 0.6,
            child: pw.Opacity(
              opacity: 0.22,
              child: pw.Text(mark, style: pw.TextStyle(fontSize: 64, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
            ),
          ),
      ]),
    ));
  }
  return doc.save();
}

class PdfExporter {
  static Future<String> save(List<String> images, String name, {PdfSize size = PdfSize.a4, String watermark = ''}) async {
    final bytes = await compute(_buildPdf, <Object>[images, size.format.width, size.format.height, watermark]);
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^\w\- ]+'), '_');
    final f = File('${dir.path}/$safe.pdf');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  static Future<void> exportAndShare(String title, List<String> images, PdfSize size) async {
    final path = await save(images, title, size: size);
    await Share.shareXFiles([XFile(path)]);
  }
}
