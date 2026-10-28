import 'package:flutter_test/flutter_test.dart';
import 'package:obd_dashboard/core/input/gear_shift_map.dart';

void main() {
  group('GearShiftMap', () {
    test('默认映射：右拨片升、左拨片降', () {
      final m = GearShiftMap.initial();
      expect(m.actionFor('GameButton5'), ShiftAction.up);
      expect(m.actionFor('GameButton4'), ShiftAction.down);
      expect(m.actionFor('Unknown'), ShiftAction.none);
    });

    test('applyPress 升挡/降挡并夹在 -1..maxGear', () {
      final m = GearShiftMap.initial();
      expect(m.applyPress('GameButton5', 1, maxGear: 6), 2); // up
      expect(m.applyPress('GameButton5', 6, maxGear: 6), 6); // 顶到上限
      expect(m.applyPress('GameButton4', 2, maxGear: 6), 1); // down
      expect(m.applyPress('GameButton4', 0, maxGear: 6), -1); // 到倒挡
      expect(m.applyPress('GameButton4', -1, maxGear: 6), -1); // 到底
      expect(m.applyPress('Unknown', 3), 3); // 未映射不变
    });

    test('rebind：同一动作只保留一个键', () {
      var m = GearShiftMap.initial();
      m = m.rebind('X', ShiftAction.up);
      // up 动作应只剩 X，原 GameButton5 被替换。
      expect(m.actionFor('X'), ShiftAction.up);
      expect(m.actionFor('GameButton5'), ShiftAction.none);
      expect(m.actionFor('GameButton4'), ShiftAction.down);
    });

    test('rebind none 解绑', () {
      var m = GearShiftMap.initial();
      m = m.rebind('GameButton4', ShiftAction.none);
      expect(m.actionFor('GameButton4'), ShiftAction.none);
    });

    test('JSON 往返', () {
      final m = GearShiftMap.initial().rebind('X', ShiftAction.up);
      final json = m.toJson();
      final back = GearShiftMap.fromJson(json);
      expect(back.actionFor('X'), ShiftAction.up);
      expect(back.actionFor('GameButton5'), ShiftAction.none);
    });
  });
}
