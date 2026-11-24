import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

// 서버 주소 (iOS 시뮬레이터는 localhost). /api/v1 은 백엔드(Spring Boot), /api/chat 은 AI 서비스. 실기기: --dart-define=AI_URL=http://<PC IP>:8787
const aiUrl = String.fromEnvironment('AI_URL', defaultValue: 'http://localhost:8787');

// 주변 검색 기준: 현재 위치 + 반경. 위치를 못 얻거나 예시를 볼 때는 데이터가 있는 성남시 전체
typedef Place = ({double latitude, double longitude});
const Place seongnam = (latitude: 37.4, longitude: 127.12);
const seongnamRadiusM = 30000;
const searchRadii = [1000, 3000, 10000, 30000];
const nearbyRadiusM = 1000; // 경고 위치 주변 위험구역

String radiusLabel(int m) => m >= 1000 ? '${m ~/ 1000}km' : '${m}m';

// 동시 다발: 웹과 같은 기준(15분 안에 3건 이상). 앱은 GPS 없이 시간만 봄.
const burstWindow = Duration(minutes: 15), burstCount = 3;

// 보행자 디바이스가 차량 감지 시 보내는 한 줄 JSON (\n 구분). 테스트 경고는 이 예시를 순서대로 보냄.
// alert_level: SAFE·CAUTION·DANGER·RELEASED. duration_ms·samples(offset_ms 는 감지 시작 기준)는 선택.
const samples = [
  '{"max_rssi":-53,"min_estimated_distance":2.8,"consecutive_count":5,"alert_level":"DANGER","vibration_triggered":true,"duration_ms":5000,'
      '"samples":[{"rssi":-72,"estimated_distance":8.1,"offset_ms":100},{"rssi":-66,"estimated_distance":5.4,"offset_ms":300},{"rssi":-53,"estimated_distance":2.8,"offset_ms":500}]}',
  '{"max_rssi":-65,"min_estimated_distance":5.2,"consecutive_count":2,"alert_level":"CAUTION","vibration_triggered":true,"duration_ms":3000}',
  '{"max_rssi":-82,"min_estimated_distance":10.4,"consecutive_count":1,"alert_level":"CAUTION","vibration_triggered":true,"duration_ms":2000}',
];

const alertDetails = NotificationDetails(
  android: AndroidNotificationDetails('vehicle_alert', '차량 접근 경고',
      importance: Importance.max, priority: Priority.high),
);

// 보행자 디바이스(device/osori_badge): Nordic UART Service 의 TX 특성 notify 로 한 줄 JSON 을 조각내 보냄
const badgeService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e', badgeTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// notify 조각을 \n 까지 이어 붙여 한 줄씩 (UTF-8 이 조각 경계에서 잘려도 됨)
Stream<String> badgeLines(Stream<List<int>> chunks) =>
    chunks.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());
final notifications = FlutterLocalNotificationsPlugin();
final app = AppState();

class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

Future<HttpClientResponse> _request(HttpClient client, String path, Object? body) async {
  final uri = Uri.parse('$aiUrl$path');
  final req = body == null ? await client.getUrl(uri) : await client.postUrl(uri);
  if (body != null) {
    // Content-Length 를 명시 (기본은 chunked 전송이라 server.py 가 본문을 못 읽음)
    final bytes = utf8.encode(jsonEncode(body));
    req.headers.contentType = ContentType.json;
    req.contentLength = bytes.length;
    req.add(bytes);
  }
  return req.close().timeout(const Duration(seconds: 120));
}

/// 서버 호출. 실패 시 사람이 읽을 메시지의 [ApiError].
Future<dynamic> api(String path, [Object? body]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final res = await _request(client, path, body);
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 300) throw ApiError('${data['message'] ?? data['error']}', res.statusCode);  // 백엔드 message, AI 서비스 error
    return data is Map && data.containsKey('success') ? data['data'] : data; // 백엔드 응답은 {success, code, message, data}
  } on ApiError {
    rethrow;
  } catch (_) {
    throw ApiError('서버($aiUrl)에 연결할 수 없습니다');
  } finally {
    client.close();
  }
}

/// 답변을 받는 대로 넘기는 /api/chat 호출. 실패 시 [ApiError] (그 전까지 받은 조각은 이미 넘어간 상태).
Stream<String> apiStream(String path, Object body) async* {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final res = await _request(client, path, body);
    if (res.statusCode != 200) {
      throw ApiError('${jsonDecode(await res.transform(utf8.decoder).join())['error']}');
    }
    // await for: yield* 와 달리 스트림 오류가 아래 catch 로 옴
    await for (final piece in res.transform(utf8.decoder).timeout(const Duration(seconds: 120))) {
      yield piece;
    }
  } on ApiError {
    rethrow;
  } catch (_) {
    throw ApiError('AI 서버($aiUrl) 연결이 끊겼습니다');
  } finally {
    client.close();
  }
}

class Alert {
  Alert(this.event);
  final DateTime time = DateTime.now();
  final Map<String, dynamic> event;
  int? eventId; // 서버에 저장된 접근 이벤트
  Map<String, dynamic>? zone; // 가장 가까운 위험구역
  bool checkedZones = false;
  String? error; // 서버 기록 실패 사유 (경고는 이미 울린 뒤)
}

String _at(DateTime t, [int length = 19]) => t.toIso8601String().substring(0, length); // 명세 예시처럼 오프셋 없음

/// 현재 위치. 권한이 없거나 못 얻으면 [ApiError].
Future<Position> _currentPosition() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw ApiError('위치 권한이 없어 현재 위치를 쓸 수 없습니다');
  }
  try {
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)));
  } catch (_) {
    throw ApiError('현재 위치를 확인하지 못했습니다');
  }
}

typedef ChatMessage = ({String role, String content});

class MapData {
  MapData({
    required this.center,
    required this.radius,
    required this.isHere,
    required this.locationError,
    required this.zones,
    required this.recent,
    required this.events,
    required this.total,
    required this.bursts,
    required this.burstRule,
  });
  final Place center;
  final int radius, total;
  final bool isHere; // false 면 성남시 전체 기준
  final String? locationError;
  final List<Map<String, dynamic>> zones, recent, events, bursts;
  final String burstRule;
}

double distanceM(Map a, Map b) {
  double rad(num d) => d * math.pi / 180;
  final h = math.pow(math.sin(rad(b['latitude'] - a['latitude']) / 2), 2) +
      math.cos(rad(a['latitude'])) * math.cos(rad(b['latitude'])) * math.pow(math.sin(rad(b['longitude'] - a['longitude']) / 2), 2);
  return 2 * 6371000 * math.asin(math.sqrt(h));
}

/// 이벤트가 속한 위험구역: 반경 안에서 가장 가까운 곳 (웹·서버와 같은 규칙)
Map<String, dynamic>? zoneOf(Map event, List<Map<String, dynamic>> zones) {
  final near = zones.where((z) => distanceM(event, z) <= z['radius']).toList()
    ..sort((a, b) => distanceM(event, a).compareTo(distanceM(event, b)));
  return near.firstOrNull;
}

class AppState extends ChangeNotifier {
  AppState() {
    Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners()); // 동시 다발 배너 만료
  }

  // 경고
  final alerts = <Alert>[];
  bool vibrate = true, notify = true, burstNotify = true; // ponytail: 메모리 보관, 앱 재시작 시 기본값
  int _sample = 0;

  // 블루투스
  BleDevice? conn;
  List<StreamSubscription> _links = [];
  String deviceName = '';
  String? deviceAddress;
  List<BleDevice> found = [];
  bool scanning = false;
  String? btMessage;

  // 지도/그래프 (GET /risk-zones, /map, /proximity-events + AI 서비스의 동시 다발 구역)
  static const eventScan = 200; // ponytail: 최근 200건만 거리로 거름. 이벤트가 많아지면 명세에 위치 조건 추가
  int searchRadius = 3000;
  bool showSeongnam = false;
  late Future<MapData> mapData = _loadMap();

  // 채팅
  final chat = <ChatMessage>[];
  bool chatting = false;
  String streaming = ''; // 받는 중인 답변

  List<Alert> get recent => alerts.where((a) => DateTime.now().difference(a.time) <= burstWindow).toList();

  void update(VoidCallback f) {
    f();
    notifyListeners();
  }

  void reloadMap() => update(() => mapData = _loadMap());

  /// 당겨서 새로고침: 실패는 지도 탭이 mapData 로 보여 줌
  Future<void> refreshMap() {
    reloadMap();
    return mapData.then((_) {}, onError: (_) {});
  }

  Future<MapData> _loadMap() async {
    Place? here;
    String? locationError;
    if (!showSeongnam) {
      try {
        here = await locate();
      } on ApiError catch (e) {
        locationError = e.message;
      }
    }
    final center = here ?? seongnam;
    final radius = here == null ? seongnamRadiusM : searchRadius;
    final query = 'latitude=${center.latitude}&longitude=${center.longitude}&radius=$radius';
    // 웹 대시보드와 같은 API
    final (zones, map, events, bursts) = await (
      api('/api/v1/risk-zones?$query'),
      api('/api/v1/map?$query'),
      api('/api/v1/proximity-events?size=$eventScan'),
      api('/api/bursts'),
    ).wait;
    final rule = bursts['params'];
    final centerMap = {'latitude': center.latitude, 'longitude': center.longitude};
    bool near(Map p) => distanceM(centerMap, p) <= radius; // 명세의 이벤트 목록에는 위치 조건이 없어 받은 뒤 거름
    return MapData(
      center: center,
      radius: radius,
      isHere: here != null,
      locationError: locationError,
      zones: List<Map<String, dynamic>>.from(zones['riskZones']),
      recent: List<Map<String, dynamic>>.from(map['recentEvents']),
      events: List<Map<String, dynamic>>.from(events['content']).where(near).toList(),
      total: events['totalElements'],
      bursts: List<Map<String, dynamic>>.from(bursts['bursts']).where(near).toList(),
      burstRule: '${rule['radius_m']}m · ${rule['window_min']}분 · ${rule['min_count']}건 이상',
    );
  }

  void setSearch({int? radius, bool? seongnamView}) {
    searchRadius = radius ?? searchRadius;
    showSeongnam = seongnamView ?? showSeongnam;
    reloadMap();
  }

  /// 위치 얻기: 테스트에서 바꿔 끼움
  Future<Place> Function() locate = () async {
    final p = await _currentPosition();
    return (latitude: p.latitude, longitude: p.longitude);
  };

  void testAlert() => onLine(samples[_sample++ % samples.length]);

  void onLine(String line) {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(line);
    } catch (_) {
      return; // 깨진 패킷 무시
    }
    if (const {'SAFE', 'RELEASED'}.contains(event['alert_level'])) return; // 대기·해제는 경고 상황이 아님
    final alert = Alert(event);
    update(() => alerts.insert(0, alert));
    // 즉시 경고가 먼저, 서버 기록은 그 뒤 (네트워크가 없어도 경고는 울림)
    if (vibrate) HapticFeedback.heavyImpact();
    if (notify) {
      notifications.show(
        id: 0,
        title: '⚠️ 차량 접근 경고',
        body: '저소음 차량이 ${event['min_estimated_distance'] ?? '?'}m 이내에 있습니다. 전방을 주시하세요.',
        notificationDetails: alertDetails,
      );
    }
    if (recent.length == burstCount && burstNotify) {
      if (vibrate) HapticFeedback.vibrate();
      notifications.show(
        id: 1,
        title: '동시 다발 경고 구역',
        body: '최근 ${burstWindow.inMinutes}분 안에 차량 접근이 $burstCount건 감지되었습니다. 전방·후방을 주시하세요.',
        notificationDetails: alertDetails,
      );
    }
    _report(alert);
  }

  /// 감지 결과 저장(POST /proximity-events, /samples) 후 주변 위험구역 조회(GET /risk-zones).
  Future<void> _report(Alert a) async {
    try {
      final at = await locate();
      a.eventId = await _saveEvent(a, at);
      final samples = a.event['samples'];
      if (samples is List && samples.isNotEmpty) {
        await api('/api/v1/proximity-events/${a.eventId}/samples', {
          'samples': [
            for (final s in samples)
              {
                'rssi': s['rssi'],
                'estimatedDistance': s['estimated_distance'],
                'measuredAt': _at(_startedAt(a).add(Duration(milliseconds: s['offset_ms'] ?? 0)), 23),
              },
          ],
        });
      }
      final near = await api('/api/v1/risk-zones?latitude=${at.latitude}&longitude=${at.longitude}&radius=$nearbyRadiusM');
      final zones = near['riskZones'] as List;
      a.zone = zones.isEmpty ? null : Map<String, dynamic>.from(zones.first);
      a.checkedZones = true;
    } on ApiError catch (e) {
      a.error = e.message;
    }
    notifyListeners();
  }

  DateTime _startedAt(Alert a) => a.time.subtract(Duration(milliseconds: a.event['duration_ms'] ?? 0));

  Future<int> _saveEvent(Alert a, Place at) async {
    final e = a.event;
    final body = {
      'latitude': at.latitude,
      'longitude': at.longitude,
      'maxRssi': e['max_rssi'],
      'minEstimatedDistance': e['min_estimated_distance'],
      'alertLevel': e['alert_level'] == 'DANGER' ? 'DANGER' : 'CAUTION', // 모르는 값도 경고로 기록
      'consecutiveCount': e['consecutive_count'],
      'vibrationTriggered': e['vibration_triggered'] ?? vibrate,
      'startedAt': _at(_startedAt(a)),
      'endedAt': _at(a.time),
    };
    try {
      return (await api('/api/v1/proximity-events', {'deviceId': await _deviceId(), ...body}))['eventId'];
    } on ApiError catch (error) {
      if (error.status != 404) rethrow;
      await _forgetDevice(); // 서버 DB 를 새로 만들어 저장해 둔 디바이스가 사라진 경우: 다시 등록
      return (await api('/api/v1/proximity-events', {'deviceId': await _deviceId(), ...body}))['eventId'];
    }
  }

  // 등록한 디바이스는 기기 주소별로 기억. 연결 전 테스트 경고는 'test' 로 묶음
  String get _deviceKey => 'deviceId:${deviceAddress ?? 'test'}';

  Future<void> _forgetDevice() async => (await SharedPreferences.getInstance()).remove(_deviceKey);

  Future<int> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_deviceKey);
    if (saved != null) return saved;
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36); // 앱을 다시 설치해도 uuid 가 겹치지 않게
    final created = await api('/api/v1/devices', {
      'deviceUuid': deviceAddress == null ? 'APP-TEST-$suffix' : 'BADGER-$deviceAddress-$suffix',
      'name': deviceAddress == null ? '앱 테스트 경고' : deviceName,
      'deviceType': deviceAddress == null ? 'ETC' : 'WEARABLE',
    });
    await prefs.setInt(_deviceKey, created['deviceId']);
    return created['deviceId'];
  }

  Future<void> sendChat(String text) async {
    update(() {
      chat.add((role: 'user', content: text));
      chatting = true;
    });
    final history = chat.where((m) => m.role != 'error').map((m) => {'role': m.role, 'content': m.content}).toList();
    String? error;
    try {
      final map = await mapData.then<MapData?>((d) => d, onError: (_) => null); // "내 주변" 질문에 현재 위치 전달
      final here = map != null && map.isHere ? {'latitude': map.center.latitude, 'longitude': map.center.longitude} : const {};
      await for (final piece in apiStream('/api/chat', {'messages': history, ...here})) {
        update(() => streaming += piece);
      }
    } on ApiError catch (e) {
      error = e.message;
    }
    final reply = streaming.trim();
    if (reply.isNotEmpty) chat.add((role: 'assistant', content: reply)); // 끊겨도 받은 부분은 남김
    if (error != null || reply.isEmpty) chat.add((role: 'error', content: error ?? 'AI 응답이 비어 있습니다'));
    update(() {
      chatting = false;
      streaming = '';
    });
  }

  // BLE: 서비스 UUID 로 8초 검색 → 연결 → TX notify 구독. 페어링(bond)은 필요 없음
  Future<void> scan() async {
    if (scanning) return;
    update(() {
      scanning = true;
      btMessage = null;
      found = [];
    });
    final results = UniversalBle.scanStream.listen((d) {
      if (!found.any((f) => f.deviceId == d.deviceId)) update(() => found.add(d));
    });
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [badgeService]),
        platformConfig: PlatformConfig(android: AndroidOptions(legacy: true)), // ESP32 는 BLE 4 광고
      );
      await Future.delayed(const Duration(seconds: 8));
      await UniversalBle.stopScan();
      if (found.isEmpty) btMessage = '주변에서 보행자 디바이스를 찾지 못했습니다. 디바이스 전원과 거리를 확인하세요.';
    } catch (e) {
      btMessage = '검색 실패: ${_bleReason(e)}';
    }
    await results.cancel();
    update(() => scanning = false);
  }

  Future<bool> connect(BleDevice d) async {
    try {
      await d.connect(timeout: const Duration(seconds: 15));
      final tx = await d.getCharacteristic(badgeTx, service: badgeService);
      conn = d;
      _links = [
        badgeLines(tx.onValueReceived).listen(onLine),
        d.connectionStream.listen((up) => up ? null : _drop(d)),
      ];
      await tx.notifications.subscribe();
      update(() {
        deviceName = d.name ?? '보행자 디바이스';
        deviceAddress = d.deviceId;
        btMessage = null;
      });
      return true;
    } catch (e) {
      _drop(d);
      d.disconnect().ignore();
      update(() => btMessage = '연결 실패: ${_bleReason(e)}');
      return false;
    }
  }

  Future<void> disconnect() async {
    final d = conn;
    if (d == null) return;
    _drop(d);
    await d.disconnect();
  }

  // 사용자 해제/기기 측 끊김 어느 쪽이 먼저 와도 한 번만 정리
  void _drop(BleDevice d) {
    if (conn != d) return;
    for (final l in _links) {
      l.cancel();
    }
    update(() {
      conn = null;
      deviceAddress = null;
    });
  }
}

String _bleReason(Object e) => e is UniversalBleException ? e.message : '$e';
