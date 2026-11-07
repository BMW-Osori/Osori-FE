// flutter test test/ui_test.dart
// 화면을 PNG 로 보기: flutter test test/ui_test.dart --update-goldens --dart-define=SHOTS=<절대 경로>
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedestrian_alert/main.dart';
import 'package:pedestrian_alert/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shots = String.fromEnvironment('SHOTS');

Future<void> loadFonts() async {
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  for (final (family, files) in [
    ('Pretendard', [for (final w in weights) 'assets/fonts/Pretendard-$w.otf']),
    ('packages/cupertino_icons/CupertinoIcons', ['packages/cupertino_icons/assets/CupertinoIcons.ttf']),
    ('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }
}

MapData fixture() {
  Map<String, dynamic> zone(int id, String name, double score, String level, double lat, double lng) => {
        'riskZoneId': id,
        'name': name,
        'riskScore': score,
        'riskLevel': level,
        'latitude': lat,
        'longitude': lng,
        'radius': 300,
        'accidentCount': 12,
        'distance': 40 * id,
      };
  final zones = [
    zone(1, '서현역 사거리', 93.7, 'HIGH', 37.3851, 127.1236),
    zone(2, '분당서울대병원 앞', 68.8, 'MEDIUM', 37.3520, 127.1230),
    zone(3, '수진역 시장골목', 22.4, 'LOW', 37.4375, 127.1400),
  ];
  Map<String, dynamic> event(int id, String level, double lat, double lng) => {
        'eventId': id,
        'startedAt': '2026-10-08T0$id:12:00',
        'occurredAt': '2026-10-08T0$id:12:00',
        'alertLevel': level,
        'minEstimatedDistance': 2.8,
        'vibrationTriggered': id.isEven,
        'latitude': lat,
        'longitude': lng,
      };
  final events = [event(1, 'DANGER', 37.3851, 127.1236), event(2, 'CAUTION', 37.3520, 127.1230), event(3, 'CAUTION', 37.5, 127.2)];
  return MapData(
    center: (latitude: 37.3851, longitude: 127.1236),
    radius: 3000,
    isHere: true,
    locationError: null,
    zones: zones,
    recent: events,
    events: events,
    total: 3,
    bursts: [
      {'zone': '서현역 사거리', 'count': 4, 'start': '2026-10-08T08:12:00', 'end': '2026-10-08T08:24:00', 'latitude': 37.3851, 'longitude': 127.1236},
    ],
    burstRule: '300m · 15분 · 3건 이상',
  );
}

/// 밝은·어두운 화면, 큰 글자·좁은 화면에서 네 탭과 구역 시트가 넘치거나 오류 없이 그려지는지
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), // 지도 타일 캐시 위치
      (_) async => Directory.systemTemp.path,
    );
    await loadFonts();
    app.notify = false;
    app.alerts.add(Alert({'min_estimated_distance': 2.8, 'max_rssi': -53, 'consecutive_count': 5, 'alert_level': 'DANGER'})
      ..checkedZones = true
      ..zone = fixture().zones.first);
    app.chat.addAll([(role: 'user', content: '서현역 사거리 위험해?'), (role: 'assistant', content: '## 서현역 사거리\n\n> 💡 위험도 **93.7점**\n\n| 시각 | 거리 |\n|---|---|\n| 08:12 | 2.8m |')]);
  });

  for (final (name, dark, scale, w, h) in [('light', false, 1.0, 390.0, 844.0), ('dark', true, 1.0, 390.0, 844.0), ('small', false, 1.3, 320.0, 568.0)]) {
    testWidgets(name, (t) async {
      t.view
        ..physicalSize = Size(w * 3, h * 3)
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: 141, bottom: 102);
      t.platformDispatcher
        ..platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light
        ..textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearAllTestValues);
      Future<void> shot(String n) async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        if (shots.isNotEmpty) await expectLater(find.byType(MaterialApp), matchesGoldenFile('$shots/$name-$n.png'));
      }

      app.mapData = Future.value(fixture()); // 테스트의 가짜 시간 안에서 끝나도록 여기서 만듦
      await t.pumpWidget(const App());
      await t.pump();
      expect(find.text('홈'), findsNothing); // 탭 막대에 이름 없음
      await shot('home');
      await t.tap(find.byIcon(CupertinoIcons.chat_bubble));
      await shot('chat');
      await t.tap(find.byIcon(CupertinoIcons.bell));
      await shot('alerts');
      await t.tap(find.byIcon(CupertinoIcons.map));
      await shot('map');
      final page = find.byType(CustomScrollView).hitTestable().first;
      await t.drag(page, const Offset(0, -700));
      await shot('map2');
      await t.tap(find.text('서현역 사거리').hitTestable().last); // 동시 다발 구역 줄
      await shot('sheet');
      expect(find.text('누적 사고'), findsOneWidget);
      await t.tapAt(const Offset(100, 100)); // 시트 닫기
      await shot('closed');
      await t.drag(page, const Offset(0, -700));
      await shot('map3');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  }
}
