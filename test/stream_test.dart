// flutter test --dart-define=AI_URL=http://127.0.0.1:18787 test/stream_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedestrian_alert/state.dart';

void main() {
  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 18787);
    server.listen((req) async {
      if (req.uri.path == '/fail') {
        req.response.statusCode = 502;
        req.response.write(jsonEncode({'error': '모델 꺼짐'}));
      } else {
        final bytes = utf8.encode('서현역 위험');
        req.response.add(bytes.sublist(0, 4)); // 한글 한 글자를 둘로 쪼개서 전송
        await req.response.flush();
        await Future.delayed(const Duration(milliseconds: 50));
        req.response.add(bytes.sublist(4));
      }
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  test('조각이 글자 중간에서 잘려도 그대로 이어 붙음', () async {
    final pieces = await apiStream('/ok', {'messages': []}).toList();
    expect(pieces.join(), '서현역 위험');
    expect(pieces.length, greaterThan(1));
  });

  test('시작 전 실패는 서버 메시지의 ApiError', () async {
    expect(apiStream('/fail', {}).drain(), throwsA(isA<ApiError>().having((e) => e.message, 'message', '모델 꺼짐')));
  });

  test('받는 동안 streaming 에 쌓이고, 끝나면 대화 기록으로 옮겨짐', () async {
    final s = AppState();
    final seen = <String>[];
    s.addListener(() => seen.add(s.streaming));
    await s.sendChat('질문');
    expect(seen, contains('서현역 위험'));
    expect(s.chat.last, (role: 'assistant', content: '서현역 위험'));
    expect(s.streaming, '');
    expect(s.chatting, false);
  });
}
