// 十套皮肤横/竖屏布局核对 golden 截图（不参与 APK 构建）。
// 生成：flutter test --update-goldens；查看 test/goldens/*.png。
//
// flutter test 默认用 TestAssetBundle，无法加载真实的 jpg/png 图片资产（背景图/立绘），
// 会把 Image.asset 渲染成「Unable to load asset」纯色块，导致 golden 像素 diff 90%+。
// 这里 mock 底层的 flutter/assets 通信通道（AssetImage 真正走的通道，不是 DefaultAssetBundle），
// 让图片按磁盘真实字节解码（与手动 FontLoader 加载中文字体同理），从而得到与真机一致的截图。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/vehicle/vehicle_profile.dart';
import 'package:obd_dashboard/features/dashboard/skins/apex_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/amber_gt_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/amber_nerv_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/cluster_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/cyan_hex_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/metro_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/nerv_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/nerv_r_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/supercar_dashboard.dart';
import 'package:obd_dashboard/features/dashboard/skins/touge_dashboard.dart';
import 'package:obd_dashboard/models/obd_data.dart';

void main() {
  final profile = VehicleProfile.presets[0];
  final data = ObdData(
    connected: true,
    source: 'demo',
    rpm: 4200,
    speed: 88,
    coolant: 92,
    oilTemp: 88,
    intakeTemp: 31,
    ambient: 24,
    voltage: 14.1,
    map: 68,
    maf: 14.6,
    load: 45,
    absLoad: 48,
    throttle: 37,
    ignAdv: 22,
    ltft: -2.5,
    fuelLevel: 72,
    gear: 4,
    tripKm: 12.4,
    tripFuel: 1.1,
    tripSec: 650,
  );

  Widget frame(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'UI')),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: child),
          ),
        ),
      );

  Widget skinFor(String id) {
    final skin = SkinRegistry.byId(id);
    switch (id) {
      case 'nerv':
        return NervDashboard(data: data, profile: profile, skin: skin);
      case 'nervr':
        return NervRDashboard(data: data, profile: profile, skin: skin);
      case 'apex':
        return ApexDashboard(data: data, profile: profile, skin: skin);
      case 'touge':
        return TougeDashboard(data: data, profile: profile, skin: skin);
      case 'cluster':
        return ClusterDashboard(data: data, profile: profile, skin: skin);
      case 'cyanhex':
        return CyanHexDashboard(data: data, profile: profile, skin: skin);
      case 'supercar':
        return SupercarDashboard(data: data, profile: profile, skin: skin);
      case 'ambergt':
        return AmberGtDashboard(data: data, profile: profile, skin: skin);
      case 'amberNerv':
        return AmberNervDashboard(data: data, profile: profile, skin: skin);
      default:
        return MetroDashboard(data: data, profile: profile, skin: skin);
    }
  }

  Future<void> loadFont(WidgetTester tester) async {
    final dseg = File('assets/fonts/DSEG7Classic-Bold.ttf').readAsBytesSync();
    await (FontLoader('DSEG7')
          ..addFont(Future.value(ByteData.view(dseg.buffer))))
        .load();
    final uiFile = File('/tmp/NotoSansSC-Regular.ttf');
    if (uiFile.existsSync()) {
      final ui = uiFile.readAsBytesSync();
      await (FontLoader('UI')
            ..addFont(Future.value(ByteData.view(ui.buffer))))
          .load();
    }
  }

  // 让测试环境能从磁盘加载真实 jpg/png 资产。AssetImage/rootBundle 底层走
  // flutter/assets 通道，给它一个空 AssetManifest（回退到原始 key），再按 key 当文件路径读字节。
  void mockDiskAssets(WidgetTester tester) {
    final imgRe = RegExp(r'\.(png|jpg|jpeg|gif|webp|bmp)$', caseSensitive: false);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets', (ByteData? message) async {
      final key = String.fromCharCodes(message!
          .buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key.endsWith('AssetManifest.bin')) {
        // StandardMessageCodec 编码的空 Map（map 类型 0x0D + size 0）。
        return ByteData.sublistView(Uint8List.fromList(const <int>[0x0D, 0x00]));
      }
      if (key.endsWith('AssetManifest.json')) {
        return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{}')));
      }
      if (imgRe.hasMatch(key)) {
        final f = File(key);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          return ByteData.view(bytes.buffer);
        }
      }
      return null;
    });
  }

  Future<void> shoot(WidgetTester tester, String id, String tag,
      double w, double h) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const shotKey = Key('shot');
    await tester.runAsync(() async {
      mockDiskAssets(tester);
      await loadFont(tester);
      await tester.pumpWidget(frame(RepaintBoundary(
        key: shotKey,
        child: SizedBox(
          width: w,
          height: h,
          child: skinFor(id),
        ),
      )));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(shotKey),
      matchesGoldenFile('goldens/${id}_$tag.png'),
    );
  }

  for (final id in ['metro', 'nerv', 'nervr', 'touge', 'apex',
      'cluster', 'cyanhex', 'supercar', 'ambergt', 'amberNerv']) {
    testWidgets('$id landscape', (tester) async {
      await shoot(tester, id, 'landscape', 1280, 720);
    });
    testWidgets('$id portrait', (tester) async {
      await shoot(tester, id, 'portrait', 720, 1280);
    });
  }
}
