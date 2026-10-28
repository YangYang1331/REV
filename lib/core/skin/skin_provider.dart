import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_registry.dart';
import 'package:obd_dashboard/core/skin/skins.dart';
import 'package:obd_dashboard/core/store/app_store.dart';

/// 当前皮肤，初始从本地存储恢复。
class SkinController extends StateNotifier<SkinDescriptor> {
  SkinController() : super(metroSkin);

  Future<void> restore() async {
    final id = await AppStore.instance.getSkin();
    if (id != null) state = SkinRegistry.byId(id);
  }

  Future<void> select(String id) async {
    state = SkinRegistry.byId(id);
    await AppStore.instance.setSkin(state.id);
  }
}

final skinProvider =
    StateNotifierProvider<SkinController, SkinDescriptor>((ref) {
  final c = SkinController();
  c.restore();
  return c;
});
