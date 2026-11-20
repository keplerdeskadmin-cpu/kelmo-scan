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

import 'package:shared_preferences/shared_preferences.dart';
import 'pdf_exporter.dart';

/// Small persisted user settings (theme is handled by ThemeProvider).
class AppSettings {
  AppSettings._();
  static final instance = AppSettings._();
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  bool get autoCapture => _p.getBool('autoCapture') ?? true;
  set autoCapture(bool v) { _p.setBool('autoCapture', v); }

  bool get askName => _p.getBool('askName') ?? true;
  set askName(bool v) { _p.setBool('askName', v); }

  String get lastRecipe => _p.getString('lastRecipe') ?? 'document';
  set lastRecipe(String v) { _p.setString('lastRecipe', v); }

  String get ocrLang => _p.getString('ocrLang') ?? 'eng';
  set ocrLang(String v) { _p.setString('ocrLang', v); }

  /// Home list: false = list (default), true = grid.
  bool get homeGrid => _p.getBool('homeGrid') ?? false;
  set homeGrid(bool v) { _p.setBool('homeGrid', v); }

  /// Home sort: date_desc (default), date_asc, name_asc, name_desc, size_desc.
  String get homeSort => _p.getString('homeSort') ?? 'date_desc';
  set homeSort(String v) { _p.setString('homeSort', v); }

  PdfSize get pdfSize =>
      PdfSize.values.firstWhere((s) => s.name == _p.getString('pdfSize'), orElse: () => PdfSize.a4);
  set pdfSize(PdfSize v) { _p.setString('pdfSize', v.name); }
}
