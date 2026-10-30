import 'package:flutter/material.dart';

/// 设置类页面统一主色（各皮肤下保持一致的青色强调）。
const Color kSettingsAccent = Color(0xFF27D6E6);

/// 分组标题。
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 设置入口行：圆角图标 + 标题/说明 + 右侧箭头。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color = kSettingsAccent,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: sub == null
          ? null
          : Text(
              sub,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
    );
  }
}

/// 通用设置子页骨架：统一背景与返回栏。
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        elevation: 0,
        title: Text(title),
      ),
      body: body,
    );
  }
}
