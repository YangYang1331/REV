import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skins.dart';

class SkinRegistry {
  static const List<SkinDescriptor> all = [
    metroSkin,
    nervSkin,
    tougeSkin,
    nervRSkin,
    apexSkin,
    clusterSkin,
    cyanHexSkin,
    supercarSkin,
    amberGtSkin,
    amberNervSkin,
  ];

  static SkinDescriptor byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => metroSkin);
}
