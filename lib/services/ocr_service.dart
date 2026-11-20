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

import 'package:flutter/services.dart';
import 'app_settings.dart';

class OcrLang {
  const OcrLang(this.label, this.code);
  final String label, code; // code = Tesseract language(s), "+" combines
  static const all = [
    OcrLang('English', 'eng'),
    OcrLang('Urdu', 'urd'),
    OcrLang('English + Urdu', 'eng+urd'),
  ];
}

/// Offline OCR through native Tesseract (see TessEngine.kt). No Google services needed.
class OcrService {
  static const _ch = MethodChannel('doc_scanner/cv');

  /// Passport machine-readable zone (bottom of the data page): whitelist A-Z 0-9 <.
  Future<String> recognizeMrz(String path) async {
    final r = await _ch.invokeMethod<String>('ocrMrz', {'path': path});
    return (r ?? '').trim();
  }

  Future<String> recognize(String path, {String? langs}) async {
    final r = await _ch.invokeMethod<String>('ocr', {'path': path, 'langs': langs ?? AppSettings.instance.ocrLang});
    return (r ?? '').trim();
  }
}
