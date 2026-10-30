/// 故障码"维修建议"层：在 [DtcDatabase] 的解释之上，补三件用户真正关心的事——
/// 有多严重（能不能继续开）、大概要花多少钱、自己能先自查什么。
///
/// 字典覆盖最常见的高频码；未收录的码按 SAE J2012 码位规则（系统域 + 故障类别）
/// 推断兜底，保证任何码都有严重度与自查建议，不出现空白。
class DtcAdvice {
  const DtcAdvice({
    required this.severity,
    required this.canDrive,
    required this.cost,
    required this.selfCheck,
    this.tip,
  });

  /// 0 = 提示（可正常使用）；1 = 警告（尽快检修）；2 = 严重（立即停机检查）。
  final int severity;

  /// 还能不能开、怎么开。
  final String canDrive;

  /// 大致维修费用区间（国内 4S / 修理厂参考价，仅作心理预期）。
  final String cost;

  /// 自己能先做的三步自查。
  final List<String> selfCheck;

  /// 额外的经验提示（可选）。
  final String? tip;

  String get severityLabel =>
      switch (severity) { 2 => '严重 · 立即处理', 1 => '警告 · 尽快检修', _ => '提示 · 可继续观察' };

  static const _known = <String, DtcAdvice>{
    // ── 失火 / 点火系统：最影响能不能继续开 ──
    'P0300': DtcAdvice(
      severity: 2,
      canDrive: '不建议继续行驶。多缸失火会让未燃烧汽油进入三元催化，几分钟就能烧坏催化器。',
      cost: '点火线圈/火花塞 300–1500 元；若已烧催化器 3000 元以上',
      selfCheck: ['听怠速是否抖动、排气是否有"突突"声', '查火花塞是否积碳/间隙过大', '查点火线圈插头是否进水氧化'],
    ),
    'P0301': DtcAdvice(
      severity: 2,
      canDrive: '低速就近维修，避免大脚油门；1 缸失火长时间行驶会烧催化器。',
      cost: '火花塞 60–200 元/支；点火线圈 200–600 元',
      selfCheck: ['与 P0302/P0303 对比判断是否单缸', '对调点火线圈看故障码是否跟着走', '检查该缸喷油嘴插头'],
    ),
    'P0302': DtcAdvice(
      severity: 2,
      canDrive: '低速就近维修，避免大脚油门；持续失火会烧催化器。',
      cost: '火花塞 60–200 元/支；点火线圈 200–600 元',
      selfCheck: ['对调点火线圈验证', '查该缸喷油嘴与线束', '测缸压排除机械问题'],
    ),
    'P0303': DtcAdvice(
      severity: 2,
      canDrive: '低速就近维修，避免大脚油门；持续失火会烧催化器。',
      cost: '火花塞 60–200 元/支；点火线圈 200–600 元',
      selfCheck: ['对调点火线圈验证', '查该缸喷油嘴与线束', '测缸压排除机械问题'],
    ),
    'P0304': DtcAdvice(
      severity: 2,
      canDrive: '低速就近维修，避免大脚油门；持续失火会烧催化器。',
      cost: '火花塞 60–200 元/支；点火线圈 200–600 元',
      selfCheck: ['对调点火线圈验证', '查该缸喷油嘴与线束', '测缸压排除机械问题'],
    ),
    'P0171': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但别长时间高速大负荷；混合气过稀会让排气温度升高。',
      cost: '清洗节气门/查漏气 100–400 元；氧传感器 400–1200 元',
      selfCheck: ['听进气歧管附近是否有"嘶嘶"漏气声', '查机油尺/机油盖是否松动（假进气）', '看长期燃油修正是否 > +15%'],
      tip: '马自达 6 常见于进气软管老化开裂，先查节气门后那根波纹管。',
    ),
    'P0172': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但油耗会明显升高，建议一周内检查。',
      cost: '清洗喷油嘴 200–600 元；氧传感器 400–1200 元',
      selfCheck: ['查空气滤芯是否严重堵塞', '闻机油是否有汽油味（喷油嘴滴漏）', '看长期燃油修正是否 < -15%'],
    ),
    'P0420': DtcAdvice(
      severity: 1,
      canDrive: '可以正常开，不影响安全；但年检尾气可能不过。',
      cost: '后氧传感器 300–900 元；三元催化器 1500–6000 元（先别急着换）',
      selfCheck: ['先排除失火与排气漏气（这两种会误报 P0420）', '读前后氧波形是否接近', '确认没有 P0300/P0171 同时存在'],
      tip: '三元催化真的坏了才会长期报；先修好失火与漏气，很多 P0420 会自己消失。',
    ),
    'P0128': DtcAdvice(
      severity: 1,
      canDrive: '可以开，冬天暖风会偏冷、油耗略高。',
      cost: '节温器 150–600 元（含工时）',
      selfCheck: ['冷启动后看水温是否 8 分钟内到 80℃ 以上', '摸上水管是否一直温热（节温器常开）', '查冷却液液位'],
    ),
    'P0113': DtcAdvice(
      severity: 1,
      canDrive: '可以开，冷启动与油耗会受影响。',
      cost: '进气温度传感器 100–400 元',
      selfCheck: ['查 MAF 插头是否插到位', '看进气温度读数是否恒定不变', '断电复位后是否复现'],
    ),
    'P0117': DtcAdvice(
      severity: 2,
      canDrive: '水温信号过低会让 ECU 误判冷车而加大喷油，不建议长途；先确认不是线路问题。',
      cost: '水温传感器 100–350 元',
      selfCheck: ['冷车时读水温是否等于环境温度', '查传感器插头是否进水', '对比仪表水温与 OBD 读数是否一致'],
    ),
    'P0118': DtcAdvice(
      severity: 2,
      canDrive: '可以低速行驶到维修点，但风扇可能常转或不开，注意别让水温冲高。',
      cost: '水温传感器 100–350 元',
      selfCheck: ['观察水温表是否异常偏高', '查风扇是否常转', '检查传感器线束'],
    ),
    'P0121': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但可能出现加速无力、怠速不稳。',
      cost: '清洗节气门 100–300 元；节气门总成 1500–4000 元',
      selfCheck: ['先清洗节气门并做节气门匹配', '查进气是否有漏气', '看怠速时节气门开度是否异常'],
    ),
    'P0135': DtcAdvice(
      severity: 0,
      canDrive: '可以正常开，油耗可能略高，年检前需处理。',
      cost: '前氧传感器 300–900 元',
      selfCheck: ['查氧传感器插头与线束', '读氧传感器加热电路电阻', '确认没有保险丝烧断'],
    ),
    'P0136': DtcAdvice(
      severity: 0,
      canDrive: '可以正常开，主要是尾气与油耗受影响。',
      cost: '后氧传感器 300–900 元',
      selfCheck: ['查传感器插头', '排除排气漏气', '对比前后氧波形'],
    ),
    'P0442': DtcAdvice(
      severity: 0,
      canDrive: '可以正常开，属于蒸发系统小泄漏，加油时可能有油气味。',
      cost: '油箱盖 50–150 元（多数是这个）；碳罐 300–800 元',
      selfCheck: ['先拧紧/更换油箱盖并清码观察', '查碳罐管路是否脱落', '确认加油后是否习惯性拧到位'],
      tip: '先换油箱盖，超过一半的 P0442 是这个原因。',
    ),
    'P0455': DtcAdvice(
      severity: 0,
      canDrive: '可以正常开，但注意车内不要有浓重汽油味（有则立即检修）。',
      cost: '油箱盖 50–150 元；碳罐电磁阀 200–600 元',
      selfCheck: ['检查油箱盖密封圈', '闻加油口附近气味', '查碳罐电磁阀是否常开'],
    ),
    'P0500': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但车速表/巡航可能失效，注意别超速。',
      cost: '车速传感器 200–600 元；线束修复 100–300 元',
      selfCheck: ['看仪表车速是否归零', '查变速箱输出轴传感器插头', '查 ABS 轮速是否正常'],
    ),
    'P0700': DtcAdvice(
      severity: 1,
      canDrive: '可以低速开到维修点，避免急加速；这是变速箱控制单元在"代报"故障。',
      cost: '需读变速箱专用码后再定，常见 500–3000 元',
      selfCheck: ['用支持变速箱模块的读码器读 TCM 子码', '查变速箱油位与油质', '闻油液是否有焦糊味'],
    ),
    'P0715': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但换挡可能顿挫；长期不理会磨损离合器片。',
      cost: '输入轴转速传感器 300–1000 元',
      selfCheck: ['观察换挡是否顿挫/迟滞', '查传感器插头与油污', '检查变速箱油'],
    ),
    'P0741': DtcAdvice(
      severity: 1,
      canDrive: '可以开，锁止离合器不锁会增加油耗与油温。',
      cost: '阀体清洗 800–2000 元；变矩器 3000 元以上',
      selfCheck: ['观察 60–80km/h 定速时转速是否偏高', '查变速箱油是否发黑', '避免长时间高负荷拖车'],
    ),
    'P0011': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但可能出现怠速不稳、加速无力。',
      cost: '机油控制阀 400–1200 元',
      selfCheck: ['先确认机油型号与油位是否正确', '查 VVT 电磁阀插头', '换油后清码观察是否复现'],
      tip: '机油太脏或粘度不对是最常见诱因，先换正确机油再看。',
    ),
    'P0016': DtcAdvice(
      severity: 2,
      canDrive: '不建议继续长距离行驶，正时偏差会损伤气门。',
      cost: '正时链条/张紧器 1500–5000 元',
      selfCheck: ['听冷启动是否有链条"哗啦"声', '查机油是否长期亏欠', '不要高转速行驶'],
    ),
    'P0017': DtcAdvice(
      severity: 2,
      canDrive: '不建议继续长距离行驶，正时偏差会损伤气门。',
      cost: '正时链条/张紧器 1500–5000 元',
      selfCheck: ['听冷启动异响', '检查机油状态', '尽快到店做正时检查'],
    ),
    'P0401': DtcAdvice(
      severity: 0,
      canDrive: '可以正常开，年检尾气可能不过。',
      cost: '清洗 EGR 阀 200–600 元；更换 500–1500 元',
      selfCheck: ['查 EGR 阀是否积碳卡滞', '看怠速是否抖动', '清码后观察是否很快复现'],
    ),
    'P0100': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但动力与油耗会受影响，避免大负荷。',
      cost: 'MAF 传感器 400–1500 元；清洗 100–200 元',
      selfCheck: ['先清洗 MAF 热丝（专用清洗剂）', '查插头与进气软管是否漏气', '读 MAF 怠速值是否约 2–4 g/s'],
    ),
    'P0101': DtcAdvice(
      severity: 1,
      canDrive: '可以开，出现加速无力时尽快检修。',
      cost: '清洗 100–300 元；MAF 400–1500 元',
      selfCheck: ['清洗 MAF 与节气门', '查空气滤芯', '查进气歧管是否漏气'],
    ),
    'P0170': DtcAdvice(
      severity: 1,
      canDrive: '可以开，油耗偏高，建议近期检查。',
      cost: '按实测原因 200–1500 元',
      selfCheck: ['看长期/短期燃油修正', '查进气漏气', '查喷油嘴雾化'],
    ),
    'P0562': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但电瓶可能亏电，避免熄火后长时间用电。',
      cost: '电瓶 400–1200 元；发电机 800–2500 元',
      selfCheck: ['怠速测电压是否 ≥13.5V', '查电瓶桩头是否氧化', '看发电机皮带是否打滑'],
    ),
    'P0560': DtcAdvice(
      severity: 0,
      canDrive: '可以开，可能出现怠速不稳或熄火后重启动困难。',
      cost: '电瓶 400–1200 元',
      selfCheck: ['测静态电压（<12.2V 说明亏电）', '查桩头与搭铁线', '看是否长期短途行驶'],
    ),
    'P2181': DtcAdvice(
      severity: 1,
      canDrive: '可以开，注意水温，夏天拥堵路段尤其要留意。',
      cost: '节温器 150–600 元；水泵 600–2000 元',
      selfCheck: ['怠速开空调看水温是否上行', '查冷却液液位与渗漏', '摸上下水管温差'],
    ),
    'P2138': DtcAdvice(
      severity: 2,
      canDrive: '不建议继续行驶：油门踏板信号异常可能进入跛行模式。',
      cost: '油门踏板总成 800–2500 元',
      selfCheck: ['清码后原地轻踩油门看是否再报', '查踏板插头', '避免急加速行驶'],
    ),
    'U0100': DtcAdvice(
      severity: 2,
      canDrive: '谨慎：与发动机 ECU 通讯丢失，可能出现无法启动。',
      cost: 'CAN 线束修复 300–1500 元；ECU 2000 元以上',
      selfCheck: ['查 OBD 口本身是否接触不良', '看其他模块是否也全丢通讯', '查电瓶电压是否过低'],
      tip: '很多 U 码是电瓶电压低或 OBD 分线器质量差导致的假故障。',
    ),
    'U0121': DtcAdvice(
      severity: 1,
      canDrive: '可以开，但 ABS/ESP 可能失效，雨天减速慢行。',
      cost: '轮速传感器 200–600 元/个',
      selfCheck: ['看仪表 ABS 灯', '查四个轮速传感器插头', '读四轮轮速是否一致'],
    ),
  };

  /// 未收录码的兜底推断：先看系统域（P/B/C/U），再看码位类别。
  static DtcAdvice fallback(String code) {
    final c = code.trim().toUpperCase();
    final sys = c.isNotEmpty ? c[0] : 'P';
    final num = int.tryParse(c.length >= 4 ? c.substring(2) : '') ?? 0;
    if (sys == 'U') {
      return const DtcAdvice(
        severity: 1,
        canDrive: '可以开，但网络通讯类故障可能影响多个功能，出现无法启动就要立刻停车检查。',
        cost: '线束/插头修复 300–1500 元',
        selfCheck: ['查电瓶电压是否偏低', '检查 OBD 分线器/延长线质量', '看是否多个 U 码同时出现'],
      );
    }
    if (sys == 'B' || sys == 'C') {
      return const DtcAdvice(
        severity: 1,
        canDrive: '可以开：车身/底盘域故障一般不影响动力，但安全气囊、ABS 类要尽快处理。',
        cost: '200–2000 元（看具体部件）',
        selfCheck: ['看仪表是否亮对应警告灯', '检查相关保险丝', '回忆近期是否涉水/拆装过内饰'],
      );
    }
    // P0000–P0999：燃油/空气计量与电路；P1000+：厂商自定义码
    if (num >= 1000) {
      return const DtcAdvice(
        severity: 1,
        canDrive: '可以开：厂商自定义码，需要对应车型的专用资料才能确诊。',
        cost: '按实测原因 200–3000 元',
        selfCheck: ['记录码并清码，看多久复现', '查该车型论坛/维修手册的码表', '留意伴随的驾驶异常（抖动/无力/异味）'],
        tip: '厂商自定义码在不同车型上含义可能完全不同，不要照搬网上的通用解释。',
      );
    }
    if (num >= 300 && num < 400) {
      return const DtcAdvice(
        severity: 1,
        canDrive: '可以开，但失火类故障别拖：未燃烧汽油会烧坏三元催化。',
        cost: '火花塞/线圈 200–1500 元',
        selfCheck: ['听怠速是否抖动', '查火花塞状态', '对调点火线圈看码是否转移'],
      );
    }
    return const DtcAdvice(
      severity: 1,
      canDrive: '可以正常行驶，建议一周内到店用专用设备进一步确诊。',
      cost: '200–1500 元（视具体原因）',
      selfCheck: ['清码后记录复现时间', '观察油耗/动力/水温有无变化', '检查近期是否刚加过油或修过车'],
    );
  }

  static DtcAdvice of(String code) =>
      _known[code.trim().toUpperCase()] ?? fallback(code);
}
