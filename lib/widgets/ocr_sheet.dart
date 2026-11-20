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
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_settings.dart';
import '../services/ocr_service.dart';
import '../theme/app_themes.dart';
import 'smart_fields_sheet.dart';

/// OCR Text Export Sheet: language picker, selectable text (RTL-aware), copy & share.
class OcrSheet extends StatefulWidget {
  const OcrSheet({super.key, required this.imagePaths, required this.controller});
  final List<String> imagePaths;
  final ScrollController controller;

  static Future<void> show(BuildContext c, List<String> imagePaths) => showModalBottomSheet(
        context: c,
        isScrollControlled: true,
        backgroundColor: c.pal.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => DraggableScrollableSheet(
          expand: false, initialChildSize: .7, minChildSize: .4, maxChildSize: .95,
          builder: (ctx, sc) => OcrSheet(imagePaths: imagePaths, controller: sc),
        ),
      );

  @override
  State<OcrSheet> createState() => _OcrSheetState();
}

class _OcrSheetState extends State<OcrSheet> {
  final _ocr = OcrService();
  String _lang = AppSettings.instance.ocrLang;
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      final parts = <String>[];
      for (var i = 0; i < widget.imagePaths.length; i++) {
        final t = await _ocr.recognize(widget.imagePaths[i], langs: _lang);
        parts.add(widget.imagePaths.length > 1 ? '— Page ${i + 1} —\n\n$t' : t);
      }
      _text = parts.join('\n\n');
    } on PlatformException catch (e) {
      _text = 'OCR failed: ${e.message ?? e.code}';
    } catch (e) {
      _text = 'OCR failed: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// More Arabic-script letters than Latin ones -> show right-to-left.
  bool get _rtl =>
      RegExp(r'[\u0600-\u06FF]').allMatches(_text).length > RegExp(r'[A-Za-z]').allMatches(_text).length;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: p.outline, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Row(children: [
          Text('Extracted Text', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
          const Spacer(),
          DropdownButton<String>(
            value: OcrLang.all.any((l) => l.code == _lang) ? _lang : 'eng',
            underline: const SizedBox(), dropdownColor: p.surface,
            style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
            items: [for (final l in OcrLang.all) DropdownMenuItem(value: l.code, child: Text(l.label))],
            onChanged: (v) { if (v != null) { _lang = v; _run(); } },
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(p.radius)),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: p.accent))
                : SingleChildScrollView(
                    controller: widget.controller,
                    child: SelectableText(
                      _text.isEmpty ? 'No text found.' : _text,
                      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                      style: TextStyle(color: p.text, fontSize: 15, height: 1.5),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent), minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
              onPressed: _text.isEmpty ? null : () async {
                await Clipboard.setData(ClipboardData(text: _text));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent), minimumSize: const Size.fromHeight(48), padding: const EdgeInsets.symmetric(horizontal: 8)),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Details'),
              onPressed: () => SmartFieldsSheet.show(context, _text, widget.imagePaths),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share'),
              onPressed: _text.isEmpty ? null : () => Share.share(_text),
            ),
          ),
        ]),
      ]),
    );
  }
}
