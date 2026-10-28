import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';

/// Metro — 玻璃磁贴仪表盘（可自定义磁贴）。
/// 深色基底 + 青色主色相 + 克制玻璃，数字用 DSEG 七段数码管。
const metroSkin = SkinDescriptor(
  id: 'metro',
  label: 'Metro',
  layout: SkinLayout.metro,
  background: Color(0xFF070B10),
  panel: Color(0x14FFFFFF),
  panelStroke: Color(0x1FFFFFFF),
  ink: Color(0xFFEAF2F6),
  dim: Color(0xFF8FA8B6),
  faint: Color(0xFF566A78),
  accent: Color(0xFF27D6E6),
  accent2: Color(0xFF7FF0E6),
  warn: Color(0xFFF2B23B),
  bad: Color(0xFFFF3B5C),
  ok: Color(0xFF2EE68A),
  glowColor: Color(0xFF127E8C),
);

/// NERV — 赤色赛博诊断风（EVA 六边形面板 + 明日香背景）。
const nervSkin = SkinDescriptor(
  id: 'nerv',
  label: 'NERV',
  layout: SkinLayout.nerv,
  background: Color(0xFF0A0304),
  panel: Color(0x16FF2A24),
  panelStroke: Color(0xFFB8181E),
  ink: Color(0xFFFFC98A),
  dim: Color(0xFFD05A4A),
  faint: Color(0xFF7A2A28),
  accent: Color(0xFFFF3B2E),
  accent2: Color(0xFFFFB02E),
  warn: Color(0xFFFFB02E),
  bad: Color(0xFFFF2A30),
  ok: Color(0xFF2EE68A),
  bgImageBase: 'dashboard_background',
  glowColor: Color(0xFF5A0E0C),
);

/// Touge — 山路水墨 JDM 风（水墨山路 + 红色光轨背景）。
const tougeSkin = SkinDescriptor(
  id: 'touge',
  label: 'Touge',
  layout: SkinLayout.touge,
  background: Color(0xFF060708),
  panel: Color(0x14FFFFFF),
  panelStroke: Color(0x33FFFFFF),
  ink: Color(0xFFF2F4F5),
  dim: Color(0xFFA9B0B6),
  faint: Color(0xFF62686E),
  accent: Color(0xFFFF2E2E),
  accent2: Color(0xFFE8EAEA),
  warn: Color(0xFFF2B23B),
  bad: Color(0xFFFF2A30),
  ok: Color(0xFF2EE68A),
  bgImageBase: 'dashboard_touge',
  glowColor: Color(0xFF4A1010),
);

/// NERV-R 赛道版 — 纯代码绘制，Haltech 换挡灯条 + 青橙温度分段条。
const nervRSkin = SkinDescriptor(
  id: 'nervr',
  label: 'NERV-R 赛道',
  layout: SkinLayout.nervr,
  background: Color(0xFF050607),
  panel: Color(0x1AFF2A24),
  panelStroke: Color(0x66B02018),
  ink: Color(0xFFFFE9D6),
  dim: Color(0xFFC07A5E),
  faint: Color(0x40FF5A3A),
  accent: Color(0xFFFF3B2E),
  accent2: Color(0xFFFFB020),
  warn: Color(0xFFFFB020),
  bad: Color(0xFFFF2A2A),
  ok: Color(0xFF27E08A),
  bgImageBase: null,
  glowColor: Color(0xFFFF3B2E),
);

/// APEX 赛博霓虹 — 品红+青色双霓虹，垂直转速条 + 中央巨车速 + 机甲立绘。
/// 纯代码绘制，纯黑底，发光全部来自元素本身，去 AI 模板感。
const apexSkin = SkinDescriptor(
  id: 'apex',
  label: 'APEX 赛博',
  layout: SkinLayout.apex,
  background: Color(0xFF06040A),
  panel: Color(0x14FF2D78),
  panelStroke: Color(0x55FF2D78),
  ink: Color(0xFFFFE8F2),
  dim: Color(0xFFC07A9A),
  faint: Color(0x40FF2D78),
  accent: Color(0xFFFF2D78),
  accent2: Color(0xFF00E5FF),
  warn: Color(0xFFFFB800),
  bad: Color(0xFFFF2A3A),
  ok: Color(0xFF27E08A),
  bgImageBase: null,
  glowColor: Color(0xFFFF2D78),
);

/// CLUSTER · 赛车橙 — 圆形转速表 + 大车速 + 数据流（移植原生 CLUSTER）。
const clusterSkin = SkinDescriptor(
  id: 'cluster',
  label: 'CLUSTER 赛车橙',
  layout: SkinLayout.cluster,
  background: Color(0xFF0A0B0D),
  panel: Color(0xFF101216),
  panelStroke: Color(0xFF1F232A),
  ink: Color(0xFFE9EBF0),
  dim: Color(0xFF8B929E),
  faint: Color(0xFF5C6370),
  accent: Color(0xFFFF4A1C),
  accent2: Color(0xFF3DDAD7),
  warn: Color(0xFFFFB020),
  bad: Color(0xFFFF3B5C),
  ok: Color(0xFF2EE68A),
  bgImageBase: null,
  glowColor: Color(0xFFFF4A1C),
);

/// CYAN_HEX · 青眼六边形 — 六边形卡 + 垂直转速条 + 点阵档位（移植原生 CYAN_HEX）。
const cyanHexSkin = SkinDescriptor(
  id: 'cyanhex',
  label: 'CYAN_HEX 青眼',
  layout: SkinLayout.cyanHex,
  background: Color(0xFF05080A),
  panel: Color(0xFF070D10),
  panelStroke: Color(0xFF2EE6E0),
  ink: Color(0xFFF2FFFE),
  dim: Color(0xFF8FC7C4),
  faint: Color(0xFF4A8684),
  accent: Color(0xFF45F6FF),
  accent2: Color(0xFF57FFF0),
  warn: Color(0xFFFFD23F),
  bad: Color(0xFFFF2E4E),
  ok: Color(0xFF2EE68A),
  bgImageBase: null,
  glowColor: Color(0xFF45F6FF),
);

/// SUPERCAR · 超跑 — 顶部水平 RPM 条 + 巨型车速 + 底部六小表（移植原生 SUPERCAR）。
const supercarSkin = SkinDescriptor(
  id: 'supercar',
  label: 'SUPERCAR 超跑',
  layout: SkinLayout.supercar,
  background: Color(0xFF08090B),
  panel: Color(0xFF0E1014),
  panelStroke: Color(0xFF22262E),
  ink: Color(0xFFF0F2F6),
  dim: Color(0xFF9AA1AD),
  faint: Color(0xFF606773),
  accent: Color(0xFFFF2A2A),
  accent2: Color(0xFFFFD08A),
  warn: Color(0xFFFFB020),
  bad: Color(0xFFFF2A2A),
  ok: Color(0xFF2EE68A),
  bgImageBase: null,
  glowColor: Color(0xFFFF2A2A),
);

/// AMBER_GT · 金瞳琥珀 — J 形转速条 + 点阵档位 + GT 徽章（移植原生 AMBER_GT）。
const amberGtSkin = SkinDescriptor(
  id: 'ambergt',
  label: 'AMBER_GT 金瞳',
  layout: SkinLayout.amberGt,
  background: Color(0xFF070502),
  panel: Color(0xFF0E0903),
  panelStroke: Color(0xFF8A5A12),
  ink: Color(0xFFFFC65A),
  dim: Color(0xFFC08A30),
  faint: Color(0xFF6E4A14),
  accent: Color(0xFFFFA818),
  accent2: Color(0xFFFFD066),
  warn: Color(0xFFFF7A1C),
  bad: Color(0xFFFF301C),
  ok: Color(0xFF2EE68A),
  bgImageBase: null,
  glowColor: Color(0xFFFFA818),
);

/// AMBER_NERV · 琥珀诊断 — 暖橙 NERV 实拍复刻：40 段黄→红转速条 + 巨车速 +
/// 无头盔立绘 + 青→红水温分段 + FUEL/MILEAGE 卡（第 10 套皮肤，纯代码绘制）。
const amberNervSkin = SkinDescriptor(
  id: 'amberNerv',
  label: '琥珀NERV 诊断',
  layout: SkinLayout.amberNerv,
  background: Color(0xFF070401),
  panel: Color(0x14FF9A20),
  panelStroke: Color(0xFF9A5A12),
  ink: Color(0xFFFFD68A),
  dim: Color(0xFFD29442),
  faint: Color(0xFF74501C),
  accent: Color(0xFFFF9A1C),
  accent2: Color(0xFFFFD24A),
  warn: Color(0xFFFF7A1C),
  bad: Color(0xFFFF3820),
  ok: Color(0xFF37E08A),
  bgImageBase: null,
  glowColor: Color(0xFFFF8A00),
);
