import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Server address + login token, kept on the phone.
class Session {
  static late SharedPreferences _p;
  static String? server, token;
  static Map<String, dynamic>? me;

  static Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    server = _p.getString('server');
    token = _p.getString('token');
    final m = _p.getString('me');
    me = m == null ? null : jsonDecode(m) as Map<String, dynamic>;
  }

  static String get myId => (me?['id'] as String?) ?? '';

  static Future<void> setServer(String s) async { server = s; await _p.setString('server', s); }

  static Future<void> setLogin(String t, Map<String, dynamic> user) async {
    token = t;
    me = user;
    await _p.setString('token', t);
    await _p.setString('me', jsonEncode(user));
  }

  static Future<void> setMe(Map<String, dynamic> user) async { me = user; await _p.setString('me', jsonEncode(user)); }

  static Future<void> logout() async {
    token = null;
    me = null;
    await _p.remove('token');
    await _p.remove('me');
  }
}
