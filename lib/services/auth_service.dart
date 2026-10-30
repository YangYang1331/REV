import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:obd_dashboard/services/cloud_service.dart';

/// 登录 / 注册结果。
class AuthResult {
  const AuthResult({
    required this.ok,
    this.error,
    this.token,
    this.username,
    this.role,
  });

  final bool ok;
  final String? error;
  final String? token;
  final String? username;
  final String? role;

  factory AuthResult.fail(String error) => AuthResult(ok: false, error: error);
}

/// 账号体系：注册 / 登录 / 退出 / 启动恢复。
/// 会话 token 持久化到 SharedPreferences，上报时由 CloudService 带上
/// `Authorization: Bearer <token>`。
class AuthService extends ChangeNotifier {
  AuthService({String? baseUrl})
      : _baseUrl = (baseUrl == null || baseUrl.isEmpty)
            ? CloudService.defaultBase
            : baseUrl;

  static const kToken = 'auth_token';
  static const kUsername = 'auth_username';
  static const kRole = 'auth_role';

  String _baseUrl;
  String get baseUrl => _baseUrl;

  String? _token;
  String? _username;
  String? _role;

  String? get token => _token;
  String? get username => _username;
  String? get role => _role;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isAdmin => _role == 'admin';

  /// 允许上层（如设置里改了云地址后）同步基址。
  void setBaseUrl(String v) {
    if (v.trim().isEmpty) return;
    _baseUrl = v.trim();
  }

  /// 启动时恢复上次登录态。
  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      _token = p.getString(kToken);
      _username = p.getString(kUsername);
      _role = p.getString(kRole);
      if (_token != null && _token!.isNotEmpty) {
        debugPrint('auth restored: $_username ($_role)');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('auth restore failed: $e');
    }
  }

  Future<AuthResult> register(String username, String password) async {
    final u = username.trim();
    if (u.isEmpty) return AuthResult.fail('请输入用户名');
    if (password.isEmpty) return AuthResult.fail('请输入密码');
    return _post('/api/auth/register', {'username': u, 'password': password});
  }

  Future<AuthResult> login(String username, String password) async {
    final u = username.trim();
    if (u.isEmpty) return AuthResult.fail('请输入用户名');
    if (password.isEmpty) return AuthResult.fail('请输入密码');
    return _post('/api/auth/login', {'username': u, 'password': password});
  }

  /// 退出：通知服务端删会话（失败忽略），本地清登录态。
  Future<void> logout() async {
    final t = _token;
    if (t != null && t.isNotEmpty) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        final req = await client.postUrl(Uri.parse('$_baseUrl/api/auth/logout'));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $t');
        req.write(jsonEncode({}));
        await req.close().timeout(const Duration(seconds: 3));
        client.close();
      } catch (_) {/* 本地退出优先，网络失败忽略 */}
    }
    await _clear();
  }

  Future<AuthResult> _post(String path, Map<String, String> body) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(Uri.parse('$_baseUrl$path'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final raw = await resp.transform(utf8.decoder).join();
      client.close();

      Map<String, dynamic> j;
      try {
        j = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return AuthResult.fail('服务器响应异常（HTTP ${resp.statusCode}）');
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300 && j['ok'] == true) {
        final token = j['token'] as String?;
        final uname = j['username'] as String?;
        final role = j['role'] as String? ?? 'user';
        if (token == null || token.isEmpty) {
          return AuthResult.fail('登录成功但未返回凭证');
        }
        await _persist(token, uname ?? body['username']!, role);
        return AuthResult(
          ok: true,
          token: token,
          username: uname ?? body['username'],
          role: role,
        );
      }
      final msg = (j['error'] as String?) ?? '操作失败（HTTP ${resp.statusCode}）';
      return AuthResult.fail(msg);
    } on SocketException {
      return AuthResult.fail('无法连接服务器，请检查网络');
    } on TimeoutException {
      return AuthResult.fail('请求超时，请稍后重试');
    } catch (e) {
      return AuthResult.fail('网络错误：$e');
    }
  }

  Future<void> _persist(String token, String username, String role) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kToken, token);
    await p.setString(kUsername, username);
    await p.setString(kRole, role);
    _token = token;
    _username = username;
    _role = role;
    notifyListeners();
  }

  Future<void> _clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kToken);
    await p.remove(kUsername);
    await p.remove(kRole);
    _token = null;
    _username = null;
    _role = null;
    notifyListeners();
  }
}
