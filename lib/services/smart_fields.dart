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

import 'dart:math';

/// One detected item (label + value) shown in the "Details" sheet.
class DetectedField {
  const DetectedField(this.label, this.value, {this.hint});
  final String label, value;
  final String? hint;
}

class MrzResult {
  MrzResult({
    required this.surname, required this.given, required this.passportNo, required this.country,
    required this.nationality, required this.dob, required this.sex, required this.expiry,
    required this.personalNo, required this.checks,
  });
  MrzResult copyWith({String? surname, String? given}) => MrzResult(
        surname: surname ?? this.surname, given: given ?? this.given, passportNo: passportNo, country: country,
        nationality: nationality, dob: dob, sex: sex, expiry: expiry, personalNo: personalNo, checks: checks,
      );
  final String surname, given, passportNo, country, nationality, dob, sex, expiry, personalNo;
  final Map<String, bool> checks; // ICAO 9303 check digits
  bool get allOk => checks.values.every((v) => v);
}

class _D {
  _D(this.pos, this.text, this.key);
  final int pos, key;
  final String text;
}

/// Finds ID numbers, dates, phones, e-mails, amounts and names in OCR text.
class SmartFields {
  static final _cnic = RegExp(r'\b\d{5}-\d{7}-\d\b');
  static final _cnicLoose = RegExp(r'\b\d{13}\b');
  static final _date = RegExp(r'\b(\d{2})[./-](\d{2})[./-](\d{4})\b');
  static final _monDate = RegExp(r'\b(\d{1,2})\s*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\s*(\d{4})\b', caseSensitive: false);
  static const _months = {'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6, 'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12};
  static final _phone = RegExp(r'(?:\+92|0092|\b0)[\s-]?3\d{2}[\s-]?\d{7}\b');
  static final _intl = RegExp(r'\+\d{1,3}[\s-]?\d{2,4}[\s-]?\d{6,8}\b');
  static final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
  static final _amount = RegExp(r'(?:Rs\.?|PKR|USD|AED|SAR|\$|£|€)\s?\d[\d,]*(?:\.\d{1,2})?', caseSensitive: false);
  static final _father = RegExp(r"Father'?s?\s*Name[:\s-]*\n?\s*([A-Z][A-Za-z.' ]{2,38})");
  static final _name = RegExp(r"\bName\b[:\s-]*\n?\s*([A-Z][A-Za-z.' ]{2,38})");

  static bool hasAny(String text) => extract(text).isNotEmpty || Mrz.parse(text) != null;

  /// Text + a clean summary line (verified MRZ data, CNIC numbers) so search finds correct values.
  static String enrich(String text) {
    final extra = <String>[];
    final m = Mrz.parse(text);
    if (m != null) {
      extra.add('PASSPORT ${m.passportNo} ${m.surname} ${m.given} ${m.dob} ${m.expiry}');
      if (RegExp(r'^\d{13}$').hasMatch(m.personalNo)) {
        extra.add('CNIC ${m.personalNo.substring(0, 5)}-${m.personalNo.substring(5, 12)}-${m.personalNo.substring(12)}');
      }
    }
    for (final id in _cnic.allMatches(text)) { extra.add('CNIC ${id.group(0)}'); }
    return extra.isEmpty ? text : '$text\n${extra.toSet().join('\n')}';
  }

  static List<DetectedField> extract(String raw) {
    final text = raw.replaceAll(RegExp(r'[“”‘’"\x27`]'), '');
    final out = <DetectedField>[];
    final seen = <String>{};
    void add(String l, String v, {String? hint}) {
      if (seen.add('$l|$v')) out.add(DetectedField(l, v, hint: hint));
    }

    // ID / CNIC numbers
    final ids = _cnic.allMatches(text).map((m) => m.group(0)!).toList();
    for (final id in ids) { add('ID / CNIC number', id); }
    if (ids.isEmpty) {
      for (final m in _cnicLoose.allMatches(text)) {
        final d = m.group(0)!;
        add('ID number (13 digits)', '${d.substring(0, 5)}-${d.substring(5, 12)}-${d.substring(12)}', hint: 'please verify');
      }
    }

    // names printed on a card
    final fm = _father.firstMatch(text);
    if (fm != null) add('Father name', fm.group(1)!.trim(), hint: 'check spelling');
    for (final m in _name.allMatches(text)) {
      final before = text.substring(max(0, m.start - 12), m.start).toLowerCase();
      if (before.contains('father')) continue;
      add('Name', m.group(1)!.trim(), hint: 'check spelling');
      break;
    }

    // passport page: "DERA GHAZI KHAN, PAK" (place of birth) and "RAFIQ, MUHAMMAD" (father/husband)
    for (final line in text.split('\n')) {
      final s = line.trim();
      final pob = RegExp(r'([A-Z][A-Z .]{2,30}),\s*PAK\b').firstMatch(s);
      if (pob != null) { add('Place of birth', '${pob.group(1)!.trim()}, PAK'); continue; }
      final fa = RegExp(r'^[^A-Za-z]*([A-Z]{3,}),\s*([A-Z][A-Z ]{2,})$').firstMatch(s);
      if (fa != null) add('Father / husband name', '${fa.group(1)}, ${fa.group(2)!.trim()}', hint: 'check spelling');
    }

    // dates: 06.10.2023 and 14 OCT 2026
    final dates = <_D>[];
    for (final m in _date.allMatches(text)) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
      if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      dates.add(_D(m.start, '${m.group(1)}.${m.group(2)}.${m.group(3)}', y * 10000 + mo * 100 + d));
    }
    for (final m in _monDate.allMatches(text)) {
      final d = int.parse(m.group(1)!), y = int.parse(m.group(3)!);
      final mo = _months[m.group(2)!.toUpperCase()]!;
      if (d < 1 || d > 31) continue;
      dates.add(_D(m.start, '${d.toString().padLeft(2, '0')}.${mo.toString().padLeft(2, '0')}.$y', y * 10000 + mo * 100 + d));
    }
    final uniq = <String, _D>{for (final d in dates) d.text: d}.values.toList();
    final looksLikeId = ids.isNotEmpty || text.toUpperCase().contains('PASSPORT');
    if (uniq.length == 3 && looksLikeId) {
      final s = [...uniq]..sort((a, b) => a.key.compareTo(b.key));
      add('Date of birth', s[0].text, hint: 'guessed from order');
      add('Date of issue', s[1].text, hint: 'guessed from order');
      add('Date of expiry', s[2].text, hint: 'guessed from order');
    } else {
      for (final d in uniq) {
        final before = text.substring(max(0, d.pos - 45), d.pos).toLowerCase();
        final label = before.contains('birth')
            ? 'Date of birth'
            : (before.contains('expir') ? 'Date of expiry' : (before.contains('issue') ? 'Date of issue' : 'Date'));
        add(label, d.text);
      }
    }

    for (final m in _phone.allMatches(text)) { add('Phone', m.group(0)!.replaceAll(RegExp(r'[\s-]'), '')); }
    for (final m in _intl.allMatches(text)) { add('Phone', m.group(0)!.replaceAll(RegExp(r'[\s-]'), '')); }
    for (final m in _email.allMatches(text)) { add('Email', m.group(0)!); }
    for (final m in _amount.allMatches(text)) { add('Amount', m.group(0)!.trim()); }
    return out;
  }
}

/// ICAO 9303 passport MRZ (TD3: two lines of 44 characters) with check-digit validation.
class Mrz {
  static const _w = [7, 3, 1];
  static const _fix = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'Z': '2', 'S': '5', 'B': '8', 'G': '6'};
  // the exact shape of line 2 (44 chars) - lets us find it even with junk before/after it
  static final _line2Re = RegExp(r'[A-Z0-9<]{9}\d[A-Z<]{3}\d{6}\d[MF<]\d{6}\d[A-Z0-9<]{14}\d\d');

  static int _val(String c) {
    if (c == '<') return 0;
    final u = c.codeUnitAt(0);
    if (u >= 48 && u <= 57) return u - 48;
    if (u >= 65 && u <= 90) return u - 55;
    return 0;
  }

  static int _check(String s) {
    var sum = 0;
    for (var i = 0; i < s.length; i++) { sum += _val(s[i]) * _w[i % 3]; }
    return sum % 10;
  }

  static String _digits(String s) => s.split('').map((c) => _fix[c] ?? c).join();

  static bool _okDigitsField(String field, String chk) {
    final c = int.tryParse(_digits(chk));
    return c != null && _check(_digits(field)) == c;
  }

  static String _fit(String s) => s.length > 44 ? s.substring(0, 44) : s.padRight(44, '<');

  static String _date(String yymmdd, {required bool birth}) {
    final d = _digits(yymmdd);
    final yy = int.tryParse(d.substring(0, 2));
    final mm = d.substring(2, 4), dd = d.substring(4, 6);
    if (yy == null) return d;
    final now = DateTime.now().year % 100;
    final year = birth ? (yy > now ? 1900 + yy : 2000 + yy) : 2000 + yy;
    return '$dd.$mm.$year';
  }

  // keep only MRZ characters: OCR adds '|', '¥', '*' etc.
  static String _clean(String l) =>
      l.replaceAll(RegExp(r'\s'), '').toUpperCase().replaceAll(RegExp(r'[«‹]'), '<').replaceAll(RegExp(r'[^A-Z0-9<]'), '');

  static List<String> _candidates(String text) =>
      [for (final l in text.split('\n')) _clean(l)].where((l) => l.length >= 28 && l.contains('<')).toList();

  static String? _line2(String l) {
    final m = _line2Re.firstMatch(l);
    if (m != null) return l.substring(m.start, m.start + 44);
    if (l.length >= 40 && l.length <= 48 && !l.startsWith('P<')) return _fit(l);
    return null;
  }

  static String? _line1(List<String> lines, int i) {
    for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
      final k = lines[j].indexOf('P<');
      if (k >= 0) return _fit(lines[j].substring(k));
    }
    return null;
  }

  static MrzResult _build(String l1, String l2) {
    final country = l1.substring(2, 5).replaceAll('<', '');
    final parts = l1.substring(5).split('<<');
    final surname = parts.first.replaceAll('<', ' ').trim();
    // OCR often reads the filler '<' as 'K': drop trailing all-K tokens from the given names
    final given = (parts.length > 1 ? parts.sublist(1).join(' ').replaceAll('<', ' ') : '')
        .replaceAll(RegExp(r'(\s+K+)+\s*$'), '')
        .trim();

    final pn = l2.substring(0, 9);
    final pnChk = l2[9];
    final nat = l2.substring(10, 13).replaceAll('<', '');
    final dobRaw = l2.substring(13, 19);
    final dobChk = l2[19];
    final sex = l2[20];
    final expRaw = l2.substring(21, 27);
    final expChk = l2[27];
    final personal = l2.substring(28, 42);
    final personalChk = l2[42];
    final finalChk = l2[43];

    final composite = pn + _digits(pnChk) + _digits(dobRaw) + _digits(dobChk) + _digits(expRaw) + _digits(expChk) +
        personal + _digits(personalChk);
    final fin = int.tryParse(_digits(finalChk));
    final personalEmpty = personal.replaceAll('<', '').isEmpty;

    final checks = <String, bool>{
      'Passport number': _check(pn) == int.tryParse(_digits(pnChk)),
      'Date of birth': _okDigitsField(dobRaw, dobChk),
      'Expiry date': _okDigitsField(expRaw, expChk),
      'Personal number': personalEmpty ? true : _check(personal) == int.tryParse(_digits(personalChk)),
      'Overall': fin != null && _check(composite) == fin,
    };
    return MrzResult(
      surname: surname, given: given, passportNo: pn.replaceAll('<', ''), country: country, nationality: nat,
      dob: _date(dobRaw, birth: true), sex: sex == '<' ? '' : sex, expiry: _date(expRaw, birth: false),
      personalNo: personal.replaceAll('<', ''), checks: checks,
    );
  }

  /// If the OCR glued a filler 'K' to a name (SARAH<<<< -> SARAHK) and the printed name appears in [hint], remove it.
  static MrzResult _fixK(MrzResult r, String? hint) {
    if (hint == null) return r;
    String fix(String name) {
      if (name.length > 3 && name.endsWith('K')) {
        final base = name.substring(0, name.length - 1);
        if (RegExp('\\b${RegExp.escape(base)}\\b').hasMatch(hint.toUpperCase())) return base;
      }
      return name;
    }
    return r.copyWith(surname: fix(r.surname), given: r.given.split(' ').map(fix).join(' '));
  }

  static MrzResult? parse(String text, {String? hintText}) {
    final lines = _candidates(text);
    for (var i = 0; i < lines.length; i++) {
      final l2 = _line2(lines[i]);
      if (l2 == null) continue;
      final l1 = _line1(lines, i);
      if (l1 == null) continue;
      final r = _build(l1, l2);
      if (r.checks.values.where((v) => v).length >= 2) return _fixK(r, hintText ?? text);
    }
    return null;
  }

  /// Human-readable reason why no MRZ was accepted (shown in the Details sheet).
  static String diagnose(String text) {
    final lines = _candidates(text);
    if (lines.isEmpty) return 'No MRZ-like line (a line with "<") found.';
    final b = StringBuffer('Lines with "<": ${lines.length}\n');
    var found2 = false;
    for (var i = 0; i < lines.length; i++) {
      final l2 = _line2(lines[i]);
      if (l2 == null) continue;
      found2 = true;
      b.writeln('Line 2: $l2');
      final l1 = _line1(lines, i);
      if (l1 == null) { b.writeln('Line 1 ("P<...") not found just above it.'); continue; }
      final r = _build(l1, l2);
      b.writeln(r.checks.entries.map((e) => '${e.key}: ${e.value ? 'ok' : 'FAIL'}').join(', '));
    }
    if (!found2) b.writeln('No 44-character line-2 pattern found.');
    return b.toString().trim();
  }
}
