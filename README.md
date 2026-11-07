# Osori-FE

저소음 차량 보행자 촉각 경고 앱 (Flutter, iOS·Android). 보행자 디바이스의 블루투스 감지 결과를 진동·알림으로 알리고, 위치를 붙여 백엔드로 보내며, 주변 사고다발지역과 AI 채팅을 보여 줍니다.

```sh
flutter pub get
flutter run --dart-define=AI_URL=https://<서버 주소>
```

`AI_URL` 은 [Osori-Presentation](https://github.com/BMW-Osori/Osori-Presentation) 을 띄운 주소입니다. Caddy 가 `/api/v1` 을 [Osori-BE](https://github.com/BMW-Osori/Osori-BE) 로, `/api/chat` 을 AI 서비스로 넘깁니다.

```sh
flutter test --dart-define=AI_URL=http://127.0.0.1:18788 test/report_test.dart   # API 호출
flutter test --dart-define=AI_URL=http://127.0.0.1:18787 test/stream_test.dart   # 채팅 스트리밍
flutter test test/ui_test.dart                                                   # 화면 넘침
```

글꼴 Pretendard(SIL OFL), 지도 © OpenStreetMap contributors. 채팅 모델 표기는 `NOTICE` 참고.
