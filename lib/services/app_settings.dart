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

  String get ocrLang => _p.getString('ocrLang2') ?? 'auto';
  set ocrLang(String v) { _p.setString('ocrLang2', v); }

  // ───────── Clear Scanner style settings
  String get themeMode => _p.getString('themeMode') ?? 'light'; // light | dark | system
  set themeMode(String v) { _p.setString('themeMode', v); }

  bool get useInAppCamera => _p.getBool('useInAppCamera') ?? true;
  set useInAppCamera(bool v) { _p.setBool('useInAppCamera', v); }

  String get cameraEngine => _p.getString('cameraEngine') ?? 'camerax'; // camerax | camera1
  set cameraEngine(String v) { _p.setString('cameraEngine', v); }

  bool get shutterSound => _p.getBool('shutterSound') ?? true;
  set shutterSound(bool v) { _p.setBool('shutterSound', v); }

  String get imagePicker => _p.getString('imagePicker') ?? 'inapp'; // inapp | system
  set imagePicker(String v) { _p.setString('imagePicker', v); }

  String get imageQuality => _p.getString('imageQuality') ?? 'high'; // low | medium | high
  set imageQuality(String v) { _p.setString('imageQuality', v); }
  int get jpegQuality => const {'low': 70, 'medium': 85, 'high': 95}[imageQuality] ?? 95;

  bool get autoSaveToGallery => _p.getBool('autoSaveToGallery') ?? true;
  set autoSaveToGallery(bool v) { _p.setBool('autoSaveToGallery', v); }

  String get galleryNameFormat => _p.getString('galleryNameFormat') ?? 'id_dt'; // id | id_dt | dt_id
  set galleryNameFormat(String v) { _p.setString('galleryNameFormat', v); }

  /// Document name template: free text prefix + optional date / time.
  String get docNamePrefix => _p.getString('docNamePrefix') ?? 'Document';
  set docNamePrefix(String v) { _p.setString('docNamePrefix', v); }
  bool get docNameDate => _p.getBool('docNameDate') ?? true;
  set docNameDate(bool v) { _p.setBool('docNameDate', v); }
  bool get docNameTime => _p.getBool('docNameTime') ?? true;
  set docNameTime(bool v) { _p.setBool('docNameTime', v); }

  String newDocumentName([DateTime? at]) {
    final n = at ?? DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    final parts = <String>[
      if (docNamePrefix.trim().isNotEmpty) docNamePrefix.trim(),
      if (docNameDate) '${n.year}-${t(n.month)}-${t(n.day)}',
      if (docNameTime) '${t(n.hour)}.${t(n.minute)}.${t(n.second)}',
    ];
    return parts.isEmpty ? 'Document' : parts.join(' ');
  }

  String get pdfResolution => _p.getString('pdfResolution') ?? 'medium'; // low | medium | high | original
  set pdfResolution(String v) { _p.setString('pdfResolution', v); }
  String get pdfOrientation => _p.getString('pdfOrientation') ?? 'auto'; // auto | portrait | landscape
  set pdfOrientation(String v) { _p.setString('pdfOrientation', v); }
  String get pdfScale => _p.getString('pdfScale') ?? 'fit'; // fit | fill
  set pdfScale(String v) { _p.setString('pdfScale', v); }

  String get emailTo => _p.getString('emailTo') ?? '';
  set emailTo(String v) { _p.setString('emailTo', v); }
  String get emailSubject => _p.getString('emailSubject') ?? '';
  set emailSubject(String v) { _p.setString('emailSubject', v); }

  bool get autoSync => _p.getBool('autoSync') ?? false;
  set autoSync(bool v) { _p.setBool('autoSync', v); }
  bool get syncWifiOnly => _p.getBool('syncWifiOnly') ?? true;
  set syncWifiOnly(bool v) { _p.setBool('syncWifiOnly', v); }
  bool get syncWarnMobile => _p.getBool('syncWarnMobile') ?? true;
  set syncWarnMobile(bool v) { _p.setBool('syncWarnMobile', v); }

  /// Home screen: dashboard (cards + quick actions) | classic (Clear Scanner list).
  String get homeStyle => _p.getString('homeStyle') ?? 'dashboard';
  set homeStyle(String v) { _p.setString('homeStyle', v); }

  bool get autoUpdateCheck => _p.getBool('autoUpdateCheck') ?? true;
  set autoUpdateCheck(bool v) { _p.setBool('autoUpdateCheck', v); }
  int get lastUpdateCheck => _p.getInt('lastUpdateCheck') ?? 0;
  set lastUpdateCheck(int v) { _p.setInt('lastUpdateCheck', v); }

  bool get homeSortAsc => _p.getBool('homeSortAsc') ?? false;
  set homeSortAsc(bool v) { _p.setBool('homeSortAsc', v); }

  /// Home list: false = list (default), true = grid.
  bool get homeGrid => _p.getBool('homeGrid') ?? false;
  set homeGrid(bool v) { _p.setBool('homeGrid', v); }

  /// Home sort field: modified (default) | created | name.
  String get homeSort {
    final v = _p.getString('homeSort') ?? 'modified';
    return const {'modified', 'created', 'name'}.contains(v) ? v : 'modified';
  }
  set homeSort(String v) { _p.setString('homeSort', v); }

  PdfSize get pdfSize =>
      PdfSize.values.firstWhere((s) => s.name == _p.getString('pdfSize'), orElse: () => PdfSize.a4);
  set pdfSize(PdfSize v) { _p.setString('pdfSize', v.name); }
}
