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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'app_settings.dart';

/// In-app update: checks the latest GitHub release and installs it with one tap
/// (Android still shows its own "Update?" confirmation).
class UpdateService {
  static const _ch = MethodChannel('doc_scanner/cv');
  static const _api = 'https://api.github.com/repos/keplerdeskadmin-cpu/kelmo-scan/releases/latest';
  static const build = int.fromEnvironment('BUILD_RUN'); // set by CI (= release number)

  /// Returns (release number, download url) when a newer release exists.
  static Future<(int, String)?> check() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(_api));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'KelmoScan');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final n = int.tryParse(RegExp(r'(\d+)$').firstMatch(j['tag_name'] as String? ?? '')?.group(1) ?? '') ?? 0;
      if (n <= build) return null;
      final abi = (await _ch.invokeMethod<String>('abi')) ?? 'arm64-v8a';
      final want = abi.contains('64') ? 'KelmoScan-arm64.apk' : 'KelmoScan-arm32.apk';
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a['name'] == want) return (n, a['browser_download_url'] as String);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<String> _download(String url, void Function(double) progress) async {
    final c = HttpClient();
    try {
      var uri = Uri.parse(url);
      HttpClientResponse res;
      var hops = 0;
      while (true) {
        final req = await c.getUrl(uri);
        req.followRedirects = false;
        req.headers.set('User-Agent', 'KelmoScan');
        res = await req.close();
        if (res.isRedirect && hops++ < 6) {
          uri = uri.resolve(res.headers.value(HttpHeaders.locationHeader)!);
          await res.drain<void>();
          continue;
        }
        break;
      }
      if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
      final f = File('${(await getTemporaryDirectory()).path}/KelmoScan-update.apk');
      final sink = f.openWrite();
      final total = res.contentLength;
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress(got / total);
      }
      await sink.close();
      return f.path;
    } finally {
      c.close(force: true);
    }
  }

  /// Auto check once a day from the home screen.
  static Future<void> autoCheck(BuildContext context) async {
    final s = AppSettings.instance;
    if (!s.autoUpdateCheck || build == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - s.lastUpdateCheck < const Duration(hours: 12).inMilliseconds) return;
    s.lastUpdateCheck = now;
    final r = await check();
    if (r != null && context.mounted) await _offer(context, r);
  }

  /// "Check for updates" from the menu.
  static Future<void> manualCheck(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    m.showSnackBar(const SnackBar(content: Text('Checking for updates…'), duration: Duration(seconds: 1)));
    final r = await check();
    if (!context.mounted) return;
    if (r == null) {
      m.showSnackBar(const SnackBar(content: Text('You have the latest version')));
    } else {
      await _offer(context, r);
    }
  }

  static Future<void> _offer(BuildContext context, (int, String) r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update available'),
        content: Text('A new version of Kelmo Scan (build ${r.$1}) is ready. Your documents are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('LATER')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('UPDATE')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final prog = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading update…'),
        content: ValueListenableBuilder<double>(
          valueListenable: prog,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v == 0 ? null : v),
            const SizedBox(height: 10),
            Text('${(v * 100).round()}%'),
          ]),
        ),
      ),
    );
    try {
      final path = await _download(r.$2, (v) => prog.value = v);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      var res = await _ch.invokeMethod<String>('installApk', {'path': path});
      if (res == 'permission' && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('One-time permission'),
            content: const Text('Turn ON "Allow from this source" for Kelmo Scan, come back, then tap INSTALL.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('INSTALL'))],
          ),
        );
        res = await _ch.invokeMethod<String>('installApk', {'path': path});
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }
}
