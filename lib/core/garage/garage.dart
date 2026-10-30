/// 多车车库：一台手机可以管多辆车，每辆车独立车型档案 / VIN / 历史记录。
///
/// 设计取舍：
///  - 车不需要登录，也不上传；车库只存本机 SharedPreferences。
///  - `id` 本地生成（时间戳 + 序号），换手机不同步，避免账号体系绑定车辆。
///  - 历史行程与加油记录都带 `vehicleId`，切车自动切换统计口径。
library;

class GarageVehicle {
  const GarageVehicle({
    required this.id,
    required this.name,
    required this.profileId,
    this.vin = '',
    this.note = '',
    this.createdTs = 0,
  });

  /// 本地稳定 id（如 v1750000000000）。
  final String id;

  /// 用户起的名字，如"我的马 6"、"家里那台 SUV"。
  final String name;

  /// 对应 [VehicleProfile.id]，决定档位反推 / 红区 / 告警阈值。
  final String profileId;

  /// 17 位 VIN（可空；读取后自动匹配车型）。
  final String vin;

  final String note;
  final int createdTs;

  static String newId([int? ts]) =>
      'v${ts ?? DateTime.now().millisecondsSinceEpoch}';

  GarageVehicle copyWith({
    String? name,
    String? profileId,
    String? vin,
    String? note,
  }) =>
      GarageVehicle(
        id: id,
        name: name ?? this.name,
        profileId: profileId ?? this.profileId,
        vin: vin ?? this.vin,
        note: note ?? this.note,
        createdTs: createdTs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profile': profileId,
        if (vin.isNotEmpty) 'vin': vin,
        if (note.isNotEmpty) 'note': note,
        if (createdTs > 0) 'ts': createdTs,
      };

  factory GarageVehicle.fromJson(Map<String, dynamic> j) => GarageVehicle(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '我的车',
        profileId: j['profile'] as String? ?? 'mazda6_2011',
        vin: j['vin'] as String? ?? '',
        note: j['note'] as String? ?? '',
        createdTs: (j['ts'] as num?)?.toInt() ?? 0,
      );
}
