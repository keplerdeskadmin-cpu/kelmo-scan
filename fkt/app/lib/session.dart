import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Server address + login token, kept on the phone.
class Session {
  static late SharedPreferences _p;
  /// Built-in server address (change from the login screen → Server settings).
  static const defaultServer = 'http://192.168.10.16:3100';
  static String? server, token;
  static bool smsGateway = false;
  static Map<String, dynamic>? me;

  static Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    server = _p.getString('server') ?? defaultServer;
    smsGateway = _p.getBool('smsGateway') ?? false;
    token = _p.getString('token');
    final m = _p.getString('me');
    me = m == null ? null : jsonDecode(m) as Map<String, dynamic>;
  }

  static String get myId => (me?['id'] as String?) ?? '';

  static Future<void> setServer(String s) async { server = s; await _p.setString('server', s); }
  static Future<void> setSmsGateway(bool v) async { smsGateway = v; await _p.setBool('smsGateway', v); }
  static bool get isAdmin => me?['role'] == 'admin';
  static bool get approved => me?['approved'] != false;
  static bool get hasName => ((me?['name'] as String?) ?? '').trim().isNotEmpty;

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
