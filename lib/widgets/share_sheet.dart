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
import 'package:share_plus/share_plus.dart';
import '../models/scan_document.dart';
import '../services/app_settings.dart';
import '../services/image_processing_service.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';

enum ShareFormat { pdf, jpg }

/// File size presets: long side in pixels, JPEG quality, and a rough size factor for the estimate.
enum ShareQuality {
  small('Small', 1200, 60, .28),
  medium('Medium', 1800, 75, .5),
  large('Large', 2600, 85, .8),
  original('Original', 0, 92, 1.0);

  const ShareQuality(this.label, this.maxSide, this.quality, this.factor);
  final String label;
  final int maxSide, quality;
  final double factor;
}

/// Share dialog: format, file name, size and PDF page size in one place.
class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.title, required this.pages});
  final String title;
  final List<ScanPage> pages;

  static Future<void> show(BuildContext c, String title, List<ScanPage> pages) => showModalBottomSheet(
        context: c,
        isScrollControlled: true,
        backgroundColor: c.pal.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ShareSheet(title: title, pages: pages),
        ),
      );

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.title);
  ShareFormat _format = ShareFormat.pdf;
  ShareQuality _quality = ShareQuality.medium;
  PdfSize _pdfSize = AppSettings.instance.pdfSize;
  int _bytes = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    int sum = 0;
    for (final p in widget.pages) {
      try { sum += File(p.imagePath).lengthSync(); } catch (_) {}
    }
    _bytes = sum;
  }

  String _est(ShareQuality q) {
    final b = _bytes * q.factor;
    if (b <= 0) return q.label;
    return '${q.label} (~${b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB'})';
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final svc = ImageProcessingService.instance;
      final imgs = <String>[];
      for (final p in widget.pages) {
        imgs.add(_quality == ShareQuality.original ? p.imagePath : await svc.shrink(p.imagePath, _quality.maxSide, _quality.quality));
      }
      var nm = _name.text.trim().replaceAll(RegExp(r'[^\w\- ]+'), '_');
      if (nm.isEmpty) nm = widget.title;
      if (_format == ShareFormat.pdf) {
        final path = await PdfExporter.save(imgs, nm, size: _pdfSize);
        await Share.shareXFiles([XFile(path)]);
      } else {
        await Share.shareXFiles([
          for (var i = 0; i < imgs.length; i++)
            XFile(imgs[i], name: imgs.length == 1 ? '$nm.jpg' : '${nm}_${i + 1}.jpg', mimeType: 'image/jpeg')
        ]);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.outline, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('Share', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
          const SizedBox(height: 12),
          SegmentedButton<ShareFormat>(
            segments: const [
              ButtonSegment(value: ShareFormat.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_outlined)),
              ButtonSegment(value: ShareFormat.jpg, label: Text('JPG images'), icon: Icon(Icons.image_outlined)),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'File name')),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.compress_rounded, color: p.accent),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButton<ShareQuality>(
                isExpanded: true, value: _quality, underline: const SizedBox(), dropdownColor: p.surface,
                items: [for (final q in ShareQuality.values) DropdownMenuItem(value: q, child: Text(_est(q)))],
                onChanged: (v) => setState(() => _quality = v ?? _quality),
              ),
            ),
          ]),
          if (_format == ShareFormat.pdf)
            Row(children: [
              Icon(Icons.crop_portrait_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<PdfSize>(
                  isExpanded: true, value: _pdfSize, underline: const SizedBox(), dropdownColor: p.surface,
                  items: [for (final s in PdfSize.values) DropdownMenuItem(value: s, child: Text('Page size: ${s.label}'))],
                  onChanged: (v) => setState(() => _pdfSize = v ?? _pdfSize),
                ),
              ),
            ]),
          const SizedBox(height: 14),
          _busy
              ? SizedBox(height: 52, child: Center(child: CircularProgressIndicator(color: p.accent)))
              : FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(52)),
                  onPressed: _go,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text('Share ${widget.pages.length} ${widget.pages.length == 1 ? 'page' : 'pages'}'),
                ),
        ]),
      ),
    );
  }
}
