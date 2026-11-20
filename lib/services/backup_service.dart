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

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'document_repository.dart';

// Top-level functions so they can run in a background isolate (no UI jank).
Future<void> _zipJob(List<Object> a) async {
  final out = a[0] as String;
  final files = (a[1] as Map).cast<String, String>();
  final dynamic enc = ZipFileEncoder(); // dynamic: archive API differs between versions (void vs Future)
  await enc.create(out);
  for (final e in files.entries) {
    await enc.addFile(File(e.value), e.key);
  }
  await enc.close();
}

Future<void> _unzipJob(List<Object> a) async {
  final dynamic extract = extractFileToDisk;
  await extract(a[0] as String, a[1] as String);
}

/// Backup = one .zip with manifest.json (folders/documents/pages) + all images.
/// Paths inside the manifest are relative, so a backup restores on any phone.
class BackupService {
  static Future<String> create() async {
    final data = await DocumentRepository.instance.buildBackupData();
    final tmp = await getTemporaryDirectory();
    final manifest = File('${tmp.path}/manifest.json');
    await manifest.writeAsString(jsonEncode(data.manifest));
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    final out = '${tmp.path}/KelmoScan_backup_${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}.zip';
    final f = File(out);
    if (f.existsSync()) f.deleteSync();
    await compute(_zipJob, <Object>[out, {'manifest.json': manifest.path, ...data.files}]);
    return out;
  }

  /// REPLACES all current data with the backup's content.
  static Future<void> restore(String zipPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/restore_tmp');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    try {
      await compute(_unzipJob, <Object>[zipPath, dir.path]);
      await DocumentRepository.instance.restoreFromDir(dir);
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }
}
