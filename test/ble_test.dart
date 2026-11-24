import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedestrian_alert/state.dart';

// 펌웨어(device/osori_badge)처럼 20바이트씩 쪼개 보내도 한 줄씩 그대로 받는지
void main() {
  test('BLE notify 조각을 줄로 합침', () async {
    final lines = [samples[0], '{"note":"한글도 조각 경계에서 잘림"}'];
    final bytes = utf8.encode('${lines.join('\n')}\n');
    final chunks = [for (var i = 0; i < bytes.length; i += 20) bytes.sublist(i, i + 20 > bytes.length ? bytes.length : i + 20)];
    expect(await badgeLines(Stream.fromIterable(chunks)).toList(), lines);
  });
}
