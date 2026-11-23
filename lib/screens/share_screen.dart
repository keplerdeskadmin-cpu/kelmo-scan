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
import '../models/scan_document.dart';
import '../services/app_settings.dart';
import '../services/doc_export.dart';
import '../services/pdf_exporter.dart';
import '../theme/app_themes.dart';
import '../widgets/cs_bars.dart';

/// Full-screen "Share" page: format, file name, file size, then where to send it.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.title, required this.pages, this.watermark = '', this.size});
  final String title;
  final List<ScanPage> pages;
  final String watermark;
  final ExportSize? size;

  static Future<void> open(BuildContext c, String title, List<ScanPage> pages, {String watermark = '', ExportSize? size}) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => ShareScreen(title: title, pages: pages, watermark: watermark, size: size)));

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.title);
  bool _pdf = true;
  late ExportSize _size = widget.size ?? ExportSize.small;
  PdfSize _page = AppSettings.instance.pdfSize;
  final _password = TextEditingController();
  bool _showPw = false;
  bool _busy = false;

  String get _n => _name.text.trim().isEmpty ? widget.title : _name.text.trim();

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() => _pdf
      ? DocExport.sharePdf(widget.pages, _n, size: _size, watermark: widget.watermark, page: _page, password: _password.text)
      : DocExport.shareJpgs(widget.pages, _n, size: _size));

  Future<void> _more(String v) =>
      _run(() => runMoreAction(context, v, widget.pages, _n, watermark: widget.watermark, password: _pdf ? _password.text : ''));

  Widget _row(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 16, color: Color(0xFF6F7777)))),
          Expanded(child: child),
        ]),
      );

  Widget _target(IconData i, Color c, String t, VoidCallback onTap) => Column(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
            child: Icon(i, color: Colors.white),
          ),
          title: Text(t, style: const TextStyle(fontSize: 17)),
          onTap: _busy ? null : onTap,
        ),
        const Divider(height: 1),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: p.appBar, titleSpacing: 0, title: const Text('Share')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
          _row(
            'Share as:',
            DropdownButton<bool>(
              isExpanded: true, value: _pdf, dropdownColor: Colors.white,
              items: const [
                DropdownMenuItem(value: true, child: Text('.pdf')),
                DropdownMenuItem(value: false, child: Text('.jpg')),
              ],
              onChanged: (v) => setState(() => _pdf = v ?? _pdf),
            ),
          ),
          _row('Filename:', TextField(controller: _name, style: const TextStyle(fontSize: 17))),
          _row(
            'File Size:',
            DropdownButton<ExportSize>(
              isExpanded: true, value: _size, dropdownColor: Colors.white,
              items: [for (final s in ExportSize.values) DropdownMenuItem(value: s, child: Text(DocExport.estimate(widget.pages, s)))],
              onChanged: (v) => setState(() => _size = v ?? _size),
            ),
          ),
          if (_pdf)
            _row(
              'Page size:',
              DropdownButton<PdfSize>(
                isExpanded: true, value: _page, dropdownColor: Colors.white,
                items: [for (final s in PdfSize.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (v) => setState(() => _page = v ?? _page),
              ),
            ),
          if (_pdf)
            _row(
              'Password:',
              TextField(
                controller: _password,
                obscureText: !_showPw,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText: 'None (optional)',
                  suffixIcon: IconButton(
                    tooltip: _showPw ? 'Hide' : 'Show',
                    icon: Icon(_showPw ? Icons.visibility_off : Icons.lock_outline),
                    onPressed: () => setState(() => _showPw = !_showPw),
                  ),
                ),
              ),
            ),
          if (widget.watermark.isNotEmpty)
            _row('Watermark:', Text(widget.watermark, style: const TextStyle(fontSize: 16))),
          const SizedBox(height: 12),
          _target(Icons.share, p.appBar, 'Share to apps (WhatsApp, Gmail, Drive…)', _share),
          _target(Icons.email, const Color(0xFFD93025), 'Send Email', () => _more('email')),
          _target(Icons.photo_library, const Color(0xFF1E88E5), 'Save to Gallery', () => _more('gallery')),
          _target(Icons.download, const Color(0xFF43A047), 'Save to storage (Download)', () => _more('storage')),
          _target(Icons.print, const Color(0xFF5F6368), 'Print', () => _more('print')),
        ]),
        if (_busy) Positioned.fill(child: Container(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: p.accent)))),
      ]),
    );
  }
}
