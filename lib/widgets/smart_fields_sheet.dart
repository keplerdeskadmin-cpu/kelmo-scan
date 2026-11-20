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
import '../services/ocr_service.dart';
import '../services/smart_fields.dart';
import '../theme/app_themes.dart';

/// "Detected details": ID/CNIC numbers, dates, names, phones, passport MRZ — each with a copy button.
class SmartFieldsSheet extends StatefulWidget {
  const SmartFieldsSheet({super.key, required this.text, required this.imagePaths, required this.controller});
  final String text;
  final List<String> imagePaths;
  final ScrollController controller;

  static Future<void> show(BuildContext c, String text, List<String> imagePaths) => showModalBottomSheet(
        context: c,
        isScrollControlled: true,
        backgroundColor: c.pal.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => DraggableScrollableSheet(
          expand: false, initialChildSize: .75, minChildSize: .4, maxChildSize: .95,
          builder: (ctx, sc) => SmartFieldsSheet(text: text, imagePaths: imagePaths, controller: sc),
        ),
      );

  @override
  State<SmartFieldsSheet> createState() => _SmartFieldsSheetState();
}

class _SmartFieldsSheetState extends State<SmartFieldsSheet> {
  late final List<DetectedField> _fields = SmartFields.extract(widget.text);
  late MrzResult? _mrz = Mrz.parse(widget.text);
  bool _scanning = false;
  String _msg = '';
  late String _diagSource = widget.text;

  @override
  void initState() {
    super.initState();
    // text already contains MRZ-like lines but they did not validate: read them again with the dedicated MRZ OCR
    if (_mrz == null && widget.text.contains('<<')) WidgetsBinding.instance.addPostFrameCallback((_) => _readMrz());
  }

  Future<void> _readMrz() async {
    setState(() { _scanning = true; _msg = ''; });
    final ocr = OcrService();
    MrzResult? found;
    for (final p in widget.imagePaths) {
      try {
        final raw = await ocr.recognizeMrz(p);
        _diagSource = raw;
        found = Mrz.parse(raw, hintText: widget.text);
      } catch (_) {}
      if (found != null) break;
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _mrz = found;
      if (found == null) _msg = 'No passport MRZ found. Photograph the data page flat, with the two lines of "<<<<" fully inside the frame.';
    });
  }

  void _copy(String t) {
    Clipboard.setData(ClipboardData(text: t));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
  }

  String _allText() {
    final b = StringBuffer();
    final m = _mrz;
    if (m != null) {
      if (RegExp(r'^\d{13}$').hasMatch(m.personalNo)) {
        b.writeln('CNIC: ${m.personalNo.substring(0, 5)}-${m.personalNo.substring(5, 12)}-${m.personalNo.substring(12)}');
      }
      b..writeln('Name: ${m.given} ${m.surname}')..writeln('Passport no: ${m.passportNo}')
        ..writeln('Nationality: ${m.nationality}')..writeln('Date of birth: ${m.dob}')
        ..writeln('Sex: ${m.sex}')..writeln('Date of expiry: ${m.expiry}');
    }
    for (final f in _fields) { b.writeln('${f.label}: ${f.value}'); }
    return b.toString().trim();
  }

  Widget _row(AppPalette p, String label, String value, {String? hint}) => ListTile(
        dense: true,
        title: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: p.text, fontSize: 16)),
        subtitle: Text(hint == null ? label : '$label • $hint', style: TextStyle(color: p.textMuted)),
        trailing: IconButton(icon: Icon(Icons.copy_rounded, color: p.accent, size: 20), onPressed: () => _copy(value)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = _mrz;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: p.outline, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Row(children: [
          Text('Detected details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.headingFont)),
          const Spacer(),
          if (_fields.isNotEmpty || m != null)
            TextButton.icon(onPressed: () => _copy(_allText()), icon: const Icon(Icons.copy_all_rounded, size: 18), label: const Text('Copy all')),
        ]),
        Expanded(
          child: ListView(controller: widget.controller, children: [
            if (m != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.accent.withAlpha(22), borderRadius: BorderRadius.circular(p.radius)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.menu_book_outlined, color: p.accent),
                    const SizedBox(width: 8),
                    Text('Passport (MRZ)', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                    const Spacer(),
                    Icon(m.allOk ? Icons.verified_rounded : Icons.warning_amber_rounded, color: m.allOk ? const Color(0xFF3DA35D) : Colors.orange, size: 20),
                    const SizedBox(width: 4),
                    Text(m.allOk ? 'All check digits OK' : 'Verify manually', style: TextStyle(color: p.textMuted, fontSize: 12)),
                  ]),
                  _row(p, 'Name', '${m.given} ${m.surname}'.trim()),
                  _row(p, 'Passport number', m.passportNo),
                  _row(p, 'Nationality / issuing', '${m.nationality} / ${m.country}'),
                  _row(p, 'Date of birth', m.dob),
                  if (m.sex.isNotEmpty) _row(p, 'Sex', m.sex),
                  _row(p, 'Date of expiry', m.expiry),
                  if (m.personalNo.isNotEmpty) _row(p, 'Personal number', m.personalNo),
                  if (RegExp(r'^\d{13}$').hasMatch(m.personalNo))
                    _row(p, 'CNIC (from MRZ)', '${m.personalNo.substring(0, 5)}-${m.personalNo.substring(5, 12)}-${m.personalNo.substring(12)}'),
                ]),
              ),
              const SizedBox(height: 10),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent), minimumSize: const Size.fromHeight(46)),
                  onPressed: _scanning ? null : _readMrz,
                  icon: _scanning
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.menu_book_outlined),
                  label: Text(_scanning ? 'Reading…' : 'Read passport MRZ'),
                ),
              ),
            if (m == null && _diagSource.contains('<'))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(Mrz.diagnose(_diagSource), style: TextStyle(color: p.textMuted, fontSize: 11, fontFamily: 'monospace')),
              ),
            if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_msg, style: TextStyle(color: p.textMuted, fontSize: 12))),
            if (_fields.isEmpty && m == null && _msg.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Nothing recognised in the text yet (ID numbers, dates, phones, e-mails, amounts).', style: TextStyle(color: p.textMuted)),
              ),
            for (final f in _fields) _row(p, f.label, f.value, hint: f.hint),
          ]),
        ),
      ]),
    );
  }
}
