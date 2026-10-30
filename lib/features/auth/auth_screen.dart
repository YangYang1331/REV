import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:obd_dashboard/data/obd_providers.dart';
import 'package:obd_dashboard/services/auth_service.dart';

/// 账号登录 / 注册页。
/// 未登录可看演示，但车辆数据上报与车队看板需要登录。
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final auth = ref.read(authProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    AuthResult r;
    try {
      r = _isRegister
          ? await auth.register(_userCtrl.text, _passCtrl.text)
          : await auth.login(_userCtrl.text, _passCtrl.text);
    } catch (e) {
      r = AuthResult.fail('操作失败：$e');
    }
    if (!mounted) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isRegister ? '注册成功，已登录' : '欢迎回来，${r.username}')),
      );
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = r.error ?? '操作失败，请重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6B3D);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_isRegister ? '注册账号' : '登录账号'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'REV 车队看板',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isRegister
                  ? '注册后即可把车辆数据同步到你的专属看板'
                  : '登录后车辆数据才会上报到车队看板',
              style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 28),
            _field(
              controller: _userCtrl,
              label: '用户名',
              icon: Icons.person_outline,
              hint: '3–20 位字母 / 数字 / 下划线',
            ),
            const SizedBox(height: 14),
            _field(
              controller: _passCtrl,
              label: '密码',
              icon: Icons.lock_outline,
              hint: _isRegister ? '至少 6 位' : '请输入密码',
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x22FF4D4D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isRegister ? '注册并登录' : '登录',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _isRegister = !_isRegister;
                        _error = null;
                      }),
              child: Text(
                _isRegister ? '已有账号？点此登录' : '没有账号？点此注册',
                style: const TextStyle(color: Color(0xFFFFB59A), fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '演示模式无需登录即可完整体验仪表盘；登录后车辆数据才会上传到车队看板。',
              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          inputFormatters: [
            LengthLimitingTextInputFormatter(32),
          ],
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            prefixIcon: Icon(icon, color: Colors.white38, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFF131A24),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF223040)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFF6B3D)),
            ),
          ),
        ),
      ],
    );
  }
}
