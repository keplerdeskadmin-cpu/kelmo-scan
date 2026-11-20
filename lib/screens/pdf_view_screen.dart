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
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/scan_document.dart';
import '../services/doc_export.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';
import '../widgets/dialogs.dart';
import 'share_screen.dart';

/// "Document.pdf" preview: every page as it will look in the PDF, with File Size + Watermark.
class PdfViewScreen extends StatefulWidget {
  const PdfViewScreen({super.key, required this.title, required this.pages});
  final String title;
  final List<ScanPage> pages;
  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  ExportSize _size = ExportSize.small;
  String _mark = '';

  Future<void> _pickSize() async {
    final v = await showDialog<ExportSize>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('File Size'),
        children: [
          for (final s in ExportSize.values)
            ListTile(
              leading: Icon(s == _size ? Icons.radio_button_checked : Icons.radio_button_off, color: context.pal.accent),
              title: Text(DocExport.estimate(widget.pages, s)),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    );
    if (v != null) setState(() => _size = v);
  }

  Future<void> _pickMark() async {
    final v = await promptText(context, 'Watermark', initial: _mark, hint: 'e.g. CONFIDENTIAL or your name (empty = none)');
    if (v != null) setState(() => _mark = v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: const Color(0xFFE4E6E6),
      appBar: AppBar(
        backgroundColor: p.appBar,
        titleSpacing: 0,
        title: Text('${widget.title}.pdf', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            color: Colors.white,
            onSelected: (v) => runMoreAction(context, v, widget.pages, widget.title, watermark: _mark),
            itemBuilder: (_) => [
              csMenuItem('print', Icons.print, 'Print'),
              csMenuItem('storage', Icons.save, 'Save to storage'),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        itemCount: widget.pages.length,
        itemBuilder: (_, i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
          child: AspectRatio(
            aspectRatio: 1 / math.sqrt2, // A4
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(child: Image.file(File(widget.pages[i].imagePath), fit: BoxFit.contain, cacheWidth: 1400)),
              if (_mark.isNotEmpty)
                Transform.rotate(
                  angle: -0.6,
                  child: Text(_mark,
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.grey.shade700.withAlpha(60))),
                ),
            ]),
          ),
        ),
      ),
      bottomNavigationBar: CsBottomBar(children: [
        CsBarButton(icon: Icons.compress, label: 'File Size', onTap: _pickSize),
        CsBarButton(icon: Icons.branding_watermark_outlined, label: 'Watermark', onTap: _pickMark),
        const Spacer(),
        CsBarButton(
          icon: Icons.share, label: 'Share',
          onTap: () => ShareScreen.open(context, widget.title, widget.pages, watermark: _mark, size: _size),
        ),
        CsMoreButton(pages: () => widget.pages, name: () => widget.title, watermark: () => _mark),
      ]),
    );
  }
}
