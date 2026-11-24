import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import 'state.dart';
import 'ui.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final connected = app.conn != null;
          final burst = app.recent.length;
          return LargeTitlePage(
            title: '보행자 촉각 경고',
            subtitle: 'Safety AI · 저소음 차량 접근 알림',
            onRefresh: app.refreshMap,
            bottomGap: 88,
            children: [
              FutureBuilder(
                future: app.mapData,
                builder: (context, snap) => _RiskCard(app.alerts.firstOrNull, snap.data),
              ),
              if (burst >= burstCount) _BurstBanner(burst),
              const SectionTitle('보행자 디바이스'),
              AppCard(
                child: ListTile(
                  leading: IconBox(connected ? Icons.bluetooth_connected : Icons.bluetooth_searching),
                  title: Text(connected ? app.deviceName : '기기 미연결', style: bold),
                  subtitle: Text(connected ? '차량 접근 신호 수신 대기 중' : '보행자 디바이스를 찾아 연결하세요', style: mutedText),
                  trailing: connected
                      ? CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), onPressed: app.disconnect, child: const Text('해제'))
                      : CupertinoButton.tinted(
                          sizeStyle: CupertinoButtonSize.small,
                          onPressed: () => showPairingSheet(context),
                          child: const Text('기기 찾기'),
                        ),
                ),
              ),
              SectionTitle('최근 경고', trailing: Text('${app.alerts.length}건', style: mutedText)),
              if (app.alerts.isEmpty) const EmptyCard("아직 경고가 없습니다. 아래 '테스트 경고'로 시연할 수 있어요."),
              for (final a in app.alerts.take(3)) AlertCard(a),
            ],
          );
        },
      );
}

class _RiskCard extends StatelessWidget {
  const _RiskCard(this.a, this.nearby);
  final Alert? a;
  final MapData? nearby; // 경고가 없을 때 현재 위치 주변 위험구역을 보여 줌

  @override
  Widget build(BuildContext context) {
    final a = this.a;
    final near = nearby != null && nearby!.isHere ? nearby!.zones.firstOrNull : null; // 가까운 순으로 옴
    final zone = a == null ? near : a.zone;
    final score = zone?['riskScore'] as num?;
    final (title, message) = switch (a) {
      null when near != null => ('${near['name']}', '내 위치에서 ${near['distance']}m · 누적 사고 ${near['accidentCount']}건'),
      null when nearby?.isHere == true => ('주변 위험구역 없음', '내 위치 ${radiusLabel(nearby!.radius)} 안에 등록된 위험구역이 없습니다.'),
      null => ('감지된 차량 없음', nearby?.locationError ?? '보행자 디바이스가 차량 접근 신호를 기다리는 중입니다.'),
      Alert(error: final e?) => ('차량 접근 감지', '${a.event['min_estimated_distance']}m 이내 차량 · $e'),
      Alert(zone: final z?) => ('${z['name']}', '${a.event['min_estimated_distance']}m 이내 차량 · 구역까지 ${z['distance']}m · 누적 사고 ${z['accidentCount']}건'),
      Alert(checkedZones: true) => ('차량 접근 감지', '${a.event['min_estimated_distance']}m 이내 차량 · 주변 위험구역 없음'),
      _ => ('차량 접근 감지', '감지 기록을 저장하고 주변 위험구역을 확인하고 있습니다...'),
    };
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          ScoreRing(score, size: 80, stroke: 8, fontSize: 22, pending: score == null && a != null && a.error == null && !a.checkedZones),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('주변 위험구역', style: mutedText),
                if (zone != null) LevelBadge('${zone['riskLevel']}'),
              ]),
              const SizedBox(height: 4),
              Text(title, style: bold.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.3, height: 1.25)),
              const SizedBox(height: 2),
              Text(message, style: mutedText),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BurstBanner extends StatelessWidget {
  const _BurstBanner(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: levelColors['HIGH'], borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('동시 다발 경고 구역', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('최근 ${burstWindow.inMinutes}분 안에 $count건 감지 · 전방·후방 주시 필수',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

/// 기기 연결: 열면 바로 BLE 검색, 찾은 기기를 눌러 연결
void showPairingSheet(BuildContext context) {
  app.scan();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: app,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('기기 연결', style: bold.copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text('주변의 보행자 디바이스(BLE)를 찾아 연결합니다.', style: mutedText),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: app.scanning ? null : app.scan,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (app.scanning) ...[const CupertinoActivityIndicator(radius: 8), const SizedBox(width: 8)],
                Text(app.scanning ? '검색 중...' : '주변 기기 검색'),
              ]),
            ),
            if (app.btMessage != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(app.btMessage!, style: mutedText)),
            if (app.found.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('찾은 기기', style: bold.copyWith(fontSize: 13, color: muted)),
              for (final d in app.found) _DeviceTile(d),
            ],
            if (app.found.isEmpty && !app.scanning && app.btMessage == null)
              Padding(padding: const EdgeInsets.only(top: 16), child: Text('표시할 기기가 없습니다.', style: mutedText)),
          ]),
        ),
      ),
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.d);
  final BleDevice d;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const IconBox(Icons.watch),
        title: Text(d.name ?? '보행자 디바이스', style: bold),
        subtitle: Text(d.rssi == null ? d.deviceId : '${d.deviceId} · ${d.rssi}dBm', style: mutedText),
        trailing: Text('연결', style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
        onTap: () async {
          if (await app.connect(d) && context.mounted) Navigator.pop(context);
        },
      );
}
