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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'document_repository.dart';
import 'ocr_service.dart';
import 'smart_fields.dart';

/// Background OCR that fills pages.ocr_text so search can look INSIDE documents.
/// Safe to call any time: only one run at a time, resumes where it stopped
/// (pages with ocr_text IS NULL are "pending"; '' means "done, no text").
class OcrIndexer {
  static bool _running = false;
  static final ValueNotifier<int> pending = ValueNotifier(0);

  static Future<void> refresh() async =>
      pending.value = await DocumentRepository.instance.pendingOcrCount();

  static Future<void> run() async {
    if (_running) return;
    _running = true;
    final repo = DocumentRepository.instance;
    final ocr = OcrService();
    try {
      while (true) {
        pending.value = await repo.pendingOcrCount();
        final batch = await repo.pagesNeedingOcr(limit: 4);
        if (batch.isEmpty) break;
        for (final pg in batch) {
          var text = '';
          try {
            text = SmartFields.enrich(await ocr.recognize(pg.imagePath));
          } on PlatformException catch (e) {
            if (e.code == 'OCR_INIT') return; // language data missing: stop, do NOT mark pages as done
          } catch (_) {}
          await repo.setOcrText(pg.id, text); // '' prevents endless retries
        }
      }
    } finally {
      _running = false;
      pending.value = await repo.pendingOcrCount();
    }
  }
}
