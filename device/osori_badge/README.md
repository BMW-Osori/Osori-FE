# OSORI 보행자 뱃지 펌웨어

ESP32-C3 SuperMini 가 비콘의 RSSI 를 스캔해 거리를 판단하고, 진동 모터를 울리면서 같은 판단을 BLE 로 폰 앱(`Osori-FE`)에 알려 줍니다.

## 빌드

| 항목 | 값 |
|---|---|
| 보드 | ESP32-C3 SuperMini |
| FQBN | `esp32:esp32:esp32c3:CDCOnBoot=cdc` |
| esp32 core | 2.0.17 |
| 라이브러리 | NimBLE-Arduino 1.4.3 |

```sh
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc device/osori_badge
arduino-cli upload  -p <COM포트> --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc device/osori_badge
arduino-cli monitor -p <COM포트> -c baudrate=115200
```

시리얼에 `v5 raw=.. smooth=.. age=..ms state=.. vib=.. ble=..` 가 100ms 마다 찍힙니다. `ble=1` 이면 폰 앱이 붙은 상태입니다.

## 배선

| 신호 | 연결 |
|---|---|
| 진동 모터 제어 | `GPIO4` → 100Ω → 2N7000 Gate (Gate–GND 10kΩ 풀다운) |
| 모터 | 스위치 출력(3.0~4.2V) → 모터 `+`, 모터 `−` → 2N7000 Drain, Source → GND |
| 전원 | TP4056 `OUT+` → 스위치 → ESP32 `5V` |

- `GPIO2`·`GPIO8`·`GPIO9` 는 부트 스트래핑 핀이라 모터 제어에 쓰지 않습니다.
- 모터는 `digitalWrite` 단속으로만 구동합니다(모터 양단 다이오드 없음 → `analogWrite` 금지).

## 비콘

- Minew MWB01, `TARGET_MAC = "c3:00:00:8c:07:53"` (대소문자 무시하고 비교)
- RSSI 문턱값: `-65` 약한 진동 진입 / `-55` 강한 진동 진입 / `-59` 강한→약한 복귀 / `-68` 완전 꺼짐
- 판단 유지 시간: 약 `0.5초`, 강 `0.4초`, 복귀 `0.3초`, 꺼짐 `0.2초`
- RSSI 는 `0.3 * 이전 + 0.7 * 현재` 로 스무딩하고, 1.8초 넘게 패킷이 없으면 신호 없음으로 봅니다.
- 진동 패턴: 약한 진동은 150ms 켜고 650ms 쉬기, 강한 진동은 연속.

## BLE (폰 앱 연동)

- 기기 이름 `OSORI-BADGE`, Nordic UART 서비스
  - 서비스 `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
  - TX(notify) `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
- 상태가 바뀔 때마다 한 줄 JSON 을 20바이트씩 나눠 notify 합니다.

```json
{"max_rssi":-52,"min_estimated_distance":0.4,"consecutive_count":2,"alert_level":"DANGER","vibration_triggered":true,"duration_ms":1200}
```

- `alert_level`: `CAUTION`(약한 진동) / `DANGER`(강한 진동)
- 앱에서는 `OSORI-BADGE` 를 찾아 연결하면 되고, 페어링 창은 뜨지 않습니다.
