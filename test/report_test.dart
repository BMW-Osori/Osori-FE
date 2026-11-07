// flutter test --dart-define=AI_URL=http://127.0.0.1:18788 test/report_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedestrian_alert/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 명세 API 순서와 요청 본문을 가짜 서버로 확인
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  final calls = <(String, Map<String, dynamic>?)>[];
  var deviceExists = true, down = false;

  setUpAll(() async {
    HttpOverrides.global = null; // 테스트 바인딩은 실제 HTTP 를 막으므로 해제
    server = await HttpServer.bind('127.0.0.1', 18788);
    server.listen((req) async {
      final text = await utf8.decoder.bind(req).join();
      calls.add((req.uri.toString(), text.isEmpty ? null : jsonDecode(text)));
      void reply(int status, Object body) {
        req.response.statusCode = status;
        req.response.write(jsonEncode(body));
      }

      if (down) {
        reply(500, {'message': '서버 오류'});
      } else if (req.uri.path == '/api/v1/devices') {
        deviceExists = true;
        reply(201, {'success': true, 'code': 'COMMON_201', 'message': '', 'data': {'deviceId': 7}}); // 백엔드 공통 응답
      } else if (req.method == 'POST' && req.uri.path == '/api/v1/proximity-events') {
        deviceExists ? reply(201, {'eventId': 125}) : reply(404, {'status': 404, 'code': 'DEVICE_NOT_FOUND', 'message': '없는 디바이스'});
      } else if (req.uri.path.endsWith('/samples')) {
        reply(201, {'eventId': 125, 'savedCount': 3});
      } else if (req.uri.path == '/api/v1/map') {
        reply(200, {'riskZones': [], 'recentEvents': []});
      } else if (req.uri.path == '/api/bursts') {
        reply(200, {
          'bursts': [
            {'zone': '가까움', 'count': 3, 'latitude': 37.386, 'longitude': 127.1235},
            {'zone': '멀리', 'count': 3, 'latitude': 37.5, 'longitude': 127.1235},
          ],
          'params': {'radius_m': 300, 'window_min': 15, 'min_count': 3},
        });
      } else if (req.method == 'GET' && req.uri.path == '/api/v1/proximity-events') {
        reply(200, {
          'content': [
            {'eventId': 1, 'latitude': 37.386, 'longitude': 127.1235},
            {'eventId': 2, 'latitude': 37.5, 'longitude': 127.1235},
          ],
          'totalElements': 2,
        });
      } else if (req.uri.path == '/api/v1/risk-zones') {
        reply(200, {
          'riskZones': [
            {'riskZoneId': 32, 'name': '서현역 사거리', 'distance': 84.3, 'riskScore': 87.2, 'riskLevel': 'HIGH', 'accidentCount': 12},
          ],
        });
      }
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  AppState newApp() => AppState()
    ..notify = false // 알림 플러그인은 테스트 환경에 없음
    ..locate = () async => (latitude: 37.385, longitude: 127.1235);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    deviceExists = true;
    down = false;
  });
  Future<void> settle(AppState a) async {
    while (a.alerts.first.eventId == null && a.alerts.first.error == null || !a.alerts.first.checkedZones && a.alerts.first.error == null) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  test('경고 → 디바이스 등록 → 이벤트·샘플 저장 → 주변 위험구역 조회', () async {
    final a = newApp();
    a.onLine(samples.first);
    expect(a.alerts.length, 1, reason: '경고는 서버 응답을 기다리지 않음');
    await settle(a);
    expect(calls.map((c) => c.$1.split('?').first), ['/api/v1/devices', '/api/v1/proximity-events', '/api/v1/proximity-events/125/samples', '/api/v1/risk-zones']);
    expect(calls[0].$2!['deviceType'], 'ETC');
    final event = calls[1].$2!;
    expect(event['deviceId'], 7);
    expect(event['latitude'], 37.385);
    expect(event['maxRssi'], -53);
    expect(event['minEstimatedDistance'], 2.8);
    expect(event['alertLevel'], 'DANGER');
    expect(event['consecutiveCount'], 5);
    expect(event['vibrationTriggered'], true);
    expect(event['startedAt'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$')));
    expect(DateTime.parse(event['endedAt']).difference(DateTime.parse(event['startedAt'])).inSeconds, inInclusiveRange(4, 6));
    final sample = (calls[2].$2!['samples'] as List).first;
    expect(sample['rssi'], -72);
    expect(sample['estimatedDistance'], 8.1);
    expect(sample['measuredAt'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}$')));
    expect(calls[3].$1, contains('latitude=37.385&longitude=127.1235&radius=1000'));
    expect(a.alerts.first.zone!['name'], '서현역 사거리');
  });

  test('두 번째 경고는 디바이스를 다시 등록하지 않음', () async {
    final a = newApp();
    a.onLine(samples[1]);
    await settle(a);
    calls.clear();
    a.onLine(samples[2]);
    await settle(a);
    expect(calls.map((c) => c.$1.split('?').first), ['/api/v1/proximity-events', '/api/v1/risk-zones'], reason: '샘플 없는 줄은 샘플 저장도 생략');
  });

  test('서버에서 디바이스가 사라졌으면 다시 등록해 저장', () async {
    SharedPreferences.setMockInitialValues({'deviceId:test': 99});
    deviceExists = false;
    final a = newApp();
    a.onLine(samples[1]);
    await settle(a);
    expect(a.alerts.first.eventId, 125);
    expect(a.alerts.first.error, isNull);
    expect(calls[1].$1, '/api/v1/devices');
    expect(calls[2].$2!['deviceId'], 7);
  });

  test('명세 밖 값과 해제·대기 처리', () async {
    final a = newApp();
    a.onLine('{"alert_level":"SAFE"}');
    a.onLine('{"alert_level":"RELEASED"}');
    a.onLine('깨진 패킷');
    expect(a.alerts, isEmpty, reason: '대기·해제·깨진 패킷은 경고가 아님');
    a.onLine('{"max_rssi":-60,"min_estimated_distance":4.0,"consecutive_count":2,"alert_level":"WARNING"}');
    await settle(a);
    expect(calls[1].$2!['alertLevel'], 'CAUTION', reason: '옛 펌웨어의 WARNING 도 경고로 기록');
  });

  test('주변 검색은 현재 위치·반경을 쓰고, 위치가 없으면 성남시 전체', () async {
    final a = newApp();
    var data = await a.mapData;
    final zones = calls.firstWhere((c) => c.$1.startsWith('/api/v1/risk-zones')).$1;
    expect(zones, contains('latitude=37.385&longitude=127.1235&radius=3000'));
    expect(calls.firstWhere((c) => c.$1.startsWith('/api/v1/map')).$1, contains('latitude=37.385&longitude=127.1235&radius=3000'));
    expect(data.isHere, true);
    expect(data.events.map((e) => e['eventId']), [1], reason: '13km 떨어진 이벤트는 제외');
    expect(data.bursts.map((b) => b['zone']), ['가까움'], reason: '동시 다발 구역도 주변만');
    calls.clear();
    a.setSearch(radius: 30000);
    data = await a.mapData;
    expect(calls.first.$1, contains('radius=30000'));
    expect(data.events.length, 2, reason: '반경을 넓히면 포함');
    calls.clear();
    a.setSearch(seongnamView: true);
    data = await a.mapData;
    expect(data.isHere, false);
    expect(calls.first.$1, contains('latitude=37.4&longitude=127.12&radius=30000'));
    final denied = newApp()..locate = () async => throw ApiError('위치 권한이 없어 현재 위치를 쓸 수 없습니다');
    data = await denied.mapData;
    expect(data.isHere, false, reason: '권한이 없으면 성남시 기준');
    expect(data.locationError, contains('위치 권한'));
  });

  test('이벤트는 반경 안에서 가장 가까운 위험구역에 묶임', () {
    Map<String, dynamic> zone(String name, double lat) => {'name': name, 'latitude': lat, 'longitude': 127.0, 'radius': 300};
    final zones = [zone('먼 곳', 37.002), zone('가까운 곳', 37.001)];
    expect(zoneOf({'latitude': 37.0005, 'longitude': 127.0}, zones)?['name'], '가까운 곳');
    expect(zoneOf({'latitude': 37.1, 'longitude': 127.0}, zones), isNull, reason: '어느 반경에도 안 들면 구역 밖');
  });

  test('서버나 위치가 안 돼도 경고는 남고 사유를 보여 줌', () async {
    down = true;
    final a = newApp();
    a.onLine(samples.first);
    expect(a.alerts.length, 1);
    await settle(a);
    expect(a.alerts.first.error, '서버 오류');
    down = false;
    final b = newApp()..locate = () async => throw ApiError('위치 권한이 없어 감지 기록을 저장하지 못했습니다');
    b.onLine(samples.first);
    await settle(b);
    expect(b.alerts.first.error, contains('위치 권한'));
  });
}
