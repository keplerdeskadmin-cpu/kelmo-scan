import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'session.dart';

class ApiError implements Exception {
  ApiError(this.message, [this.code = 0]);
  final String message;
  final int code;
  @override
  String toString() => message;
}

/// HTTP calls to the FKT server.
class Api {
  static String get base => Session.server ?? '';
  static Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (Session.token != null) 'Authorization': 'Bearer ${Session.token}',
      };

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> j = {};
    try { j = r.body.isEmpty ? {} : jsonDecode(r.body) as Map<String, dynamic>; } catch (_) {}
    if (r.statusCode >= 400) throw ApiError((j['error'] as String?) ?? 'Server error ${r.statusCode}', r.statusCode);
    return j;
  }

  static Future<Map<String, dynamic>> get(String p) async {
    try {
      return _decode(await http.get(Uri.parse('$base$p'), headers: _h).timeout(const Duration(seconds: 20)));
    } on SocketException {
      throw ApiError('Cannot reach the server. Check internet / server address.');
    }
  }

  static Future<Map<String, dynamic>> post(String p, [Map<String, dynamic>? body]) async {
    try {
      return _decode(await http
          .post(Uri.parse('$base$p'), headers: _h, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 25)));
    } on SocketException {
      throw ApiError('Cannot reach the server. Check internet / server address.');
    }
  }

  /// Uploads a file; returns {id, name, mime, size}.
  static Future<Map<String, dynamic>> upload(File f, String name, String mime) async {
    final r = await http.post(
      Uri.parse('$base/api/upload'),
      headers: {
        'Authorization': 'Bearer ${Session.token}',
        'x-filename': Uri.encodeComponent(name),
        'Content-Type': mime,
      },
      body: await f.readAsBytes(),
    ).timeout(const Duration(minutes: 5));
    return _decode(r);
  }

  static String fileUrl(String id) => '$base/files/$id?token=${Session.token}';

  static String get wsUrl {
    final u = base.replaceFirst(RegExp(r'^http'), 'ws');
    return '$u/ws?token=${Session.token}';
  }

  /// Downloads a received file into the cache (once) and returns its path.
  static Future<String> download(String id, String name) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/fkt_files');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File('${dir.path}/${id}_$safe');
    if (f.existsSync() && f.lengthSync() > 0) return f.path;
    final r = await http.get(Uri.parse(fileUrl(id))).timeout(const Duration(minutes: 5));
    if (r.statusCode != 200) throw ApiError('Download failed (${r.statusCode})');
    await f.writeAsBytes(r.bodyBytes);
    return f.path;
  }
}
