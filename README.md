# Osori-FE

저소음 차량 보행자 촉각 경고 앱 (Flutter, iOS·Android). 보행자 디바이스의 블루투스 감지 결과를 진동·알림으로 알리고, 위치를 붙여 백엔드로 보내며, 주변 사고다발지역과 AI 채팅을 보여 줍니다.

```sh
flutter pub get
flutter run                                                  # 배포 서버(https://43-200-19-220.sslip.io)에 연결
flutter run --dart-define=AI_URL=http://localhost:8787       # 로컬 서버 (실기기는 http://<PC IP>:8787)
```

서버 주소 하나로 백엔드와 AI 서비스를 함께 씁니다. 그 주소의 Caddy 가 `/api/v1` 을 [Osori-BE](https://github.com/BMW-Osori/Osori-BE) 로, `/api/chat`·`/api/bursts` 를 AI 서비스([Osori-Presentation](https://github.com/BMW-Osori/Osori-Presentation))로 넘깁니다.

```sh
flutter test --dart-define=AI_URL=http://127.0.0.1:18788 test/report_test.dart   # API 호출
flutter test --dart-define=AI_URL=http://127.0.0.1:18787 test/stream_test.dart   # 채팅 스트리밍
flutter test test/ui_test.dart                                                   # 화면 넘침
flutter test test/ble_test.dart                                                  # BLE 조각 → 한 줄 JSON
```

글꼴 Pretendard(SIL OFL), 지도 © OpenStreetMap contributors. 채팅 모델 표기는 `NOTICE` 참고.

## 함께 쓰는 저장소

| 저장소 | 역할 |
| --- | --- |
| [Osori-BE](https://github.com/BMW-Osori/Osori-BE) | 백엔드 (Spring Boot, PostgreSQL) |
| [Osori-Presentation](https://github.com/BMW-Osori/Osori-Presentation) | 시연 사이트와 AI 서비스 |
| [Osori-QWEN](https://github.com/BMW-Osori/Osori-QWEN) | 채팅 모델 튜닝 (Qwen2.5-3B) |
