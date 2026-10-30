/// 诊断报告 PDF 生成。
///
/// 中文排版不依赖内置字体：先把每一页用 Flutter 画布画成位图
/// （系统字体渲染，中文/符号都不会变豆腐块），再按 A4 逐页嵌入 PDF。
/// 这样 APK 不需要额外的 CJK 字体资源，报告在任何国产 ROM 上都能正常显示。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:obd_dashboard/core/diagnostic/dtc_database.dart';
import 'package:obd_dashboard/core/obd/deep_diagnostic.dart';

/// 报告数据（由界面层采集后传入，纯数据，便于单测）。
class DiagnosticReportData {
  const DiagnosticReportData({
    required this.generatedAt,
    required this.appVersion,
    required this.vehicleName,
    this.vin,
    this.adapterName,
    this.readiness,
    this.stored = const [],
    this.pending = const [],
    this.permanent = const [],
    this.freeze,
    this.connected = true,
  });

  final DateTime generatedAt;
  final String appVersion;
  final String vehicleName;
  final String? vin;
  final String? adapterName;
  final ReadinessReport? readiness;
  final List<String> stored;
  final List<String> pending;
  final List<String> permanent;
  final FreezeFrame? freeze;
  final bool connected;
}

class DiagnosticReport {
  const DiagnosticReport._();

  static const double _pageW = 595;
  static const double _pageH = 842;
  static const double _margin = 36;
  static const double _bottom = 40;
  static const double _headerH = 58;
  static const double _contentW = _pageW - _margin * 2;

  static const Color _ink = Color(0xFF15222C);
  static const Color _dim = Color(0xFF5A6B7A);
  static const Color _accent = Color(0xFF0E7490);
  static const Color _ok = Color(0xFF15803D);
  static const Color _warn = Color(0xFFB45309);
  static const Color _line = Color(0xFFD8E0E6);

  /// 生成 PDF 字节（2 倍分辨率位图页）。
  ///
  /// 自己拼 PDF：页面内容已经是位图，用不到任何排版库，
  /// 省掉第三方 PDF 依赖（车机包体积卡得紧，50KB 都要算）。
  static Future<Uint8List> renderBytes(DiagnosticReportData data) async {
    final painter = _PagePainter();
    _layout(painter, data);
    final images = await painter.finish();

    final pages = <Uint8List>[];
    final sizes = <List<int>>[];
    for (final img in images) {
      final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width;
      final h = img.height;
      img.dispose();
      if (raw == null) continue;
      pages.add(_rgbaToRgb(raw.buffer.asUint8List(raw.offsetInBytes,
          raw.lengthInBytes), w * h));
      sizes.add([w, h]);
    }
    return _buildPdf(pages, sizes, data.appVersion);
  }

  /// 去掉 alpha 通道（页面底色已是不透明白，直接丢 alpha 即可）。
  static Uint8List _rgbaToRgb(Uint8List rgba, int pixels) {
    final rgb = Uint8List(pixels * 3);
    var j = 0;
    for (var i = 0; i < pixels; i++) {
      final s = i * 4;
      rgb[j++] = rgba[s];
      rgb[j++] = rgba[s + 1];
      rgb[j++] = rgba[s + 2];
    }
    return rgb;
  }

  /// 组装 PDF：Catalog / Pages / 每页（Page + Image XObject + Content）。
  static Uint8List _buildPdf(
      List<Uint8List> pages, List<List<int>> sizes, String version) {
    final out = BytesBuilder();
    final offsets = <int>[];
    void w(String s) => out.add(latin1.encode(s));
    void begin(int n) {
      while (offsets.length <= n) {
        offsets.add(0);
      }
      offsets[n] = out.length;
      w('$n 0 obj\n');
    }

    // 简体消息只用 ASCII；元数据用英文，避免 PDF 头里出现非 Latin-1 字符。
    final infoNo = 3 + pages.length * 3;
    final total = infoNo + 1;
    final pageW = _pageW.toStringAsFixed(2);
    final pageH = _pageH.toStringAsFixed(2);

    w('%PDF-1.4\n');
    begin(1);
    w('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
    begin(2);
    final kids = <String>[
      for (var i = 0; i < pages.length; i++) '${3 + i * 3} 0 R'
    ].join(' ');
    w('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>\nendobj\n');

    final zlib = ZLibCodec();
    for (var i = 0; i < pages.length; i++) {
      final pno = 3 + i * 3; // page
      final ino = pno + 1; // image
      final cno = pno + 2; // content
      final w0 = sizes[i][0];
      final h0 = sizes[i][1];
      final pix = zlib.encode(pages[i]);
      final content = latin1.encode(
          'q $pageW 0 0 $pageH 0 0 cm /Im0 Do Q\n');

      begin(pno);
      w('<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 $pageW $pageH] '
          '/Resources << /XObject << /Im0 $ino 0 R >> >> '
          '/Contents $cno 0 R >>\nendobj\n');

      begin(ino);
      w('<< /Type /XObject /Subtype /Image /Width $w0 /Height $h0 '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
          '/Filter /FlateDecode /Length ${pix.length} >>\nstream\n');
      out.add(pix);
      w('\nendstream\nendobj\n');

      begin(cno);
      w('<< /Length ${content.length} >>\nstream\n');
      out.add(content);
      w('endstream\nendobj\n');
    }

    begin(infoNo);
    w('<< /Title (REV Vehicle Diagnostic Report) '
        '/Producer (REV $version) /Creator (REV $version) >>\nendobj\n');

    final xref = out.length;
    w('xref\n0 $total\n');
    w('0000000000 65535 f \n');
    for (var i = 1; i < total; i++) {
      w('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    w('trailer\n<< /Size $total /Root 1 0 R /Info $infoNo 0 R >>\n');
    w('startxref\n$xref\n%%EOF\n');
    return out.toBytes();
  }

  /// 生成并保存到应用文档目录，返回文件。
  static Future<File> save(DiagnosticReportData data) async {
    final bytes = await renderBytes(data);
    final dir = await getApplicationDocumentsDirectory();
    final d = data.generatedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'rev_report_${d.year}${two(d.month)}${two(d.day)}'
        '_${two(d.hour)}${two(d.minute)}.pdf';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ── 排版 ──

  static void _layout(_PagePainter p, DiagnosticReportData d) {
    final d0 = d.generatedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${d0.year}-${two(d0.month)}-${two(d0.day)} '
        '${two(d0.hour)}:${two(d0.minute)}';

    // 车辆信息
    p.section('车辆信息');
    p.kv('车型', d.vehicleName);
    p.kv('车架号 VIN', d.vin ?? '未读取');
    p.kv('适配器', d.adapterName ?? (d.connected ? '已连接' : '未连接'));
    p.kv('报告时间', time);
    p.kv('应用版本', 'REV ${d.appVersion}');
    p.gap(10);

    // 排放就绪
    final r = d.readiness;
    p.section('排放就绪（Mode 01 PID 01）');
    if (r == null) {
      p.text('未读取到就绪状态：ECU 未应答或当前未连接。', color: _dim);
    } else {
      p.kv('故障灯 MIL', r.milOn ? '点亮' : '未点亮',
          valueColor: r.milOn ? _warn : _ok);
      p.kv('ECU 故障码数量', '${r.dtcCount} 个');
      p.kv('就绪结论', r.ready ? '全部完成' : '还有 ${r.incomplete.length} 项未完成',
          valueColor: r.ready ? _ok : _warn);
      if (r.monitors.isNotEmpty) {
        p.gap(4);
        p.monitorGrid(r.monitors);
      }
      if (r.incomplete.isNotEmpty) {
        p.gap(2);
        p.text('未完成项：${r.incomplete.map((m) => m.name).join('、')}',
            color: _warn, size: 9.5);
        p.text('提示：年检前建议先完成一段包含冷启动的混合路况行驶，让监测项自然跑完。',
            color: _dim, size: 9);
      }
    }
    p.gap(10);

    // 故障码
    p.section('已存故障码（Mode 03）');
    _codes(p, d.stored, '未读取到已存故障码。');
    p.gap(8);
    p.section('待定故障码（Mode 07）');
    _codes(p, d.pending, '无待定故障码。');
    p.gap(8);
    p.section('永久故障码（Mode 0A）');
    _codes(p, d.permanent, '无永久故障码（或该车不支持 Mode 0A）。');
    p.gap(10);

    // 冻结帧：整块不下跨页，避免只剩一行掉到下一页。
    final f = d.freeze;
    if (f != null && !f.isEmpty) {
      final rows = (f.dtc == null ? 0 : 1) + f.fields.length;
      p.reserve(52 + rows * 17.0);
    }
    p.section('冻结帧（故障瞬间工况）');
    if (f == null) {
      p.text('未读取冻结帧。', color: _dim);
    } else if (f.isEmpty) {
      p.text('本车 ECU 未提供冻结帧。', color: _dim);
    } else {
      if (f.dtc != null) p.kv('触发故障码', f.dtc!, valueColor: _warn);
      for (final e in f.fields) {
        p.kv(e.label, e.display);
      }
    }
    p.gap(14);

    p.text(
      '说明：本报告由 REV 通过 OBD-II 标准服务（Mode 01/02/03/07/0A）读取，'
      '仅反映 ECU 当前公开的数据；部分厂商自定义监测项与 Mode 06 车载监控结果'
      '未纳入本报告，确诊请结合 4S 店/维修厂诊断仪。',
      color: _dim,
      size: 8.5,
    );
  }

  static void _codes(_PagePainter p, List<String> codes, String empty) {
    if (codes.isEmpty) {
      p.text(empty, color: _dim);
      return;
    }
    for (final c in codes) {
      final info = DtcDatabase.lookup(c);
      p.codeEntry(c, info);
    }
  }
}

/// 一页一画布的分页画笔。
class _PagePainter {
  final List<ui.Picture> _pictures = [];
  ui.PictureRecorder? _rec;
  Canvas? _canvas;
  double _y = 0;
  int _pageNo = 0;

  static const double _pageW = DiagnosticReport._pageW;
  static const double _pageH = DiagnosticReport._pageH;
  static const double _margin = DiagnosticReport._margin;
  static const double _bottom = DiagnosticReport._bottom;
  static const double _headerH = DiagnosticReport._headerH;
  static const double _ratio = 2;
  static const double _contentW = DiagnosticReport._contentW;
  static const Color _ink = DiagnosticReport._ink;
  static const Color _dim = DiagnosticReport._dim;
  static const Color _accent = DiagnosticReport._accent;
  static const Color _ok = DiagnosticReport._ok;
  static const Color _warn = DiagnosticReport._warn;
  static const Color _line = DiagnosticReport._line;

  double get _floor => _pageH - _bottom;

  void _startPage() {
    _rec = ui.PictureRecorder();
    _canvas = Canvas(_rec!)..scale(_ratio);
    _pageNo++;
    final c = _canvas!;
    c.drawRect(
      const Rect.fromLTWH(0, 0, _pageW, _pageH),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 0, _pageW, _headerH),
      Paint()..color = const Color(0xFF0B0F14),
    );
    _drawText(c, 'REV 车辆诊断报告',
        x: _margin,
        y: 18,
        size: 16,
        weight: FontWeight.w700,
        color: const Color(0xFFFFFFFF),
        maxWidth: _contentW - 120);
    _drawText(c, '第 $_pageNo 页',
        x: _pageW - _margin - 60,
        y: 26,
        size: 9,
        color: const Color(0xFF9FB2C0),
        maxWidth: 60);
    _y = _headerH + 20;
  }

  void _finishPage() {
    if (_rec == null) return;
    _pictures.add(_rec!.endRecording());
    _rec = null;
    _canvas = null;
  }

  void ensure(double h) {
    if (_canvas == null || _y + h > _floor) {
      _finishPage();
      _startPage();
    }
  }

  Future<List<ui.Image>> finish() async {
    _finishPage();
    final out = <ui.Image>[];
    for (final pic in _pictures) {
      out.add(await pic.toImage(
        (_pageW * _ratio).round(),
        (_pageH * _ratio).round(),
      ));
      pic.dispose();
    }
    return out;
  }

  double _drawText(Canvas c, String text,
      {required double x,
      double y = 0,
      double size = 10.5,
      FontWeight weight = FontWeight.w400,
      Color color = _ink,
      double height = 1.45,
      double maxWidth = _contentW}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size, fontWeight: weight, color: color, height: height),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(c, Offset(x, y));
    final h = tp.height;
    tp.dispose();
    return h;
  }

  /// 画一行正文，自动分页。
  void text(String s,
      {Color color = _ink,
      double size = 10.5,
      FontWeight weight = FontWeight.w400}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: weight, height: 1.5)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentW);
    final h = tp.height;
    tp.dispose();
    ensure(h + 2);
    final used = _drawText(_canvas!, s,
        x: _margin,
        y: _y,
        size: size,
        color: color,
        weight: weight,
        height: 1.5);
    _y += used + 2;
  }

  /// 预约一块高度：当前页放不下时先翻页。
  void reserve(double h) => ensure(h);

  void gap(double v) {
    if (_canvas != null) _y += v;
  }

  void section(String title) {
    ensure(40);
    final c = _canvas!;
    c.drawRect(
      Rect.fromLTWH(_margin, _y + 4, 3, 11),
      Paint()..color = _accent,
    );
    final h = _drawText(c, title,
        x: _margin + 10,
        y: _y,
        size: 12,
        weight: FontWeight.w700,
        color: _ink);
    _y += h + 4;
    c.drawLine(
      Offset(_margin, _y),
      Offset(_pageW - _margin, _y),
      Paint()
        ..color = _line
        ..strokeWidth = 0.8,
    );
    _y += 8;
  }

  void kv(String label, String value, {Color? valueColor}) {
    const labelW = 118.0;
    final tp = TextPainter(
      text: TextSpan(
          text: value,
          style: TextStyle(
              fontSize: 10, color: valueColor ?? _ink, height: 1.4)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentW - labelW);
    final h = tp.height;
    tp.dispose();
    ensure(h + 3);
    final c = _canvas!;
    _drawText(c, label,
        x: _margin, y: _y, size: 9.5, color: _dim, maxWidth: labelW - 6);
    _drawText(c, value,
        x: _margin + labelW,
        y: _y,
        size: 10,
        color: valueColor ?? _ink,
        maxWidth: _contentW - labelW);
    _y += h + 3;
  }

  void codeEntry(String code, DtcInfo? info) {
    final title = info?.title ?? '未收录的故障码（按 SAE J2012 分类规则）';
    final desc = info?.desc ?? '暂无本地释义，建议用诊断仪读取厂商说明。';
    final fix = info?.suggestion;
    const indent = 10.0;
    final tp1 = TextPainter(
      text: TextSpan(
          text: title,
          style: const TextStyle(fontSize: 10, color: _ink, height: 1.35)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentW - 60);
    final tp2 = TextPainter(
      text: TextSpan(
          text: desc,
          style: const TextStyle(fontSize: 9, color: _dim, height: 1.4)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _contentW - indent);
    final tp3 = fix == null
        ? null
        : (TextPainter(
            text: TextSpan(
                text: '处理建议：$fix',
                style: const TextStyle(
                    fontSize: 9, color: Color(0xFF3B4A56), height: 1.4)),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: _contentW - indent));
    final h = tp1.height + 3 + tp2.height + (tp3 == null ? 0 : 3 + tp3.height);
    ensure(h + 10);
    final c = _canvas!;
    final y0 = _y;
    // 码标签
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(_margin, y0, 46, 14), const Radius.circular(3)),
      Paint()..color = _accent.withValues(alpha: 0.12),
    );
    _drawText(c, code,
        x: _margin + 6, y: y0 + 2, size: 9, weight: FontWeight.w700,
        color: _accent, maxWidth: 40);
    _drawText(c, title,
        x: _margin + 54, y: y0 - 1, size: 10, weight: FontWeight.w600,
        maxWidth: _contentW - 60);
    var y = y0 + tp1.height + 2;
    _drawText(c, desc, x: _margin + indent, y: y, size: 9, color: _dim,
        maxWidth: _contentW - indent);
    y += tp2.height + 3;
    if (tp3 != null && fix != null) {
      _drawText(c, '处理建议：$fix',
          x: _margin + indent, y: y, size: 9,
          color: const Color(0xFF3B4A56), maxWidth: _contentW - indent);
    }
    _y = y0 + h + 10;
    tp1.dispose();
    tp2.dispose();
    tp3?.dispose();
  }

  void monitorGrid(List<ReadinessMonitor> monitors) {
    const colW = _contentW / 2;
    final rows = (monitors.length + 1) ~/ 2;
    ensure(rows * 15 + 6);
    final c = _canvas!;
    for (var i = 0; i < monitors.length; i++) {
      final m = monitors[i];
      final col = i ~/ rows;
      final row = i % rows;
      final x = _margin + col * colW;
      final y = _y + row * 15;
      final color = m.complete ? _ok : _warn;
      c.drawCircle(Offset(x + 3, y + 6), 2.4, Paint()..color = color);
      _drawText(c, m.name,
          x: x + 11, y: y - 1, size: 9.5, color: _ink, maxWidth: colW - 60);
      _drawText(c, m.complete ? '完成' : '未完成',
          x: x + colW - 52, y: y - 1, size: 8.5, color: color, maxWidth: 46);
    }
    _y += rows * 15 + 6;
  }
}
