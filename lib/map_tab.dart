import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'state.dart';
import 'ui.dart';

// 웹과 같은 지도 톤: grayscale(1) brightness(1.06) contrast(.9), 어두운 화면은 grayscale(1) invert(1) brightness(.85) contrast(.85)
ColorFilter get _mapTone {
  final (g, offset) = isDark ? (-0.7225, 203.36) : (0.954, 12.75);
  return ColorFilter.matrix([
    0.2126 * g, 0.7152 * g, 0.0722 * g, 0, offset, //
    0.2126 * g, 0.7152 * g, 0.0722 * g, 0, offset, //
    0.2126 * g, 0.7152 * g, 0.0722 * g, 0, offset, //
    0, 0, 0, 1, 0,
  ]);
}

TextStyle get axisStyle => TextStyle(color: muted, fontSize: 11);
TextStyle get smallMuted => TextStyle(color: muted, fontSize: 13);
const _tabular = [FontFeature.tabularFigures()];

/// 웹 대시보드와 같은 내용: 검색 기준 → KPI → 지도 → 동시 다발 구역 → 구역 위험도 → 시간대별 → 이벤트. 구역 상세는 누르면 시트로
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with SingleTickerProviderStateMixin {
  final map = MapController();
  AnimationController? fly; // 처음 움직일 때 만듦
  VoidCallback? flyStep;
  int? selected;
  String? fittedTo; // 카메라를 맞춘 검색 기준

  @override
  void dispose() {
    fly?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => FutureBuilder(
      future: app.mapData,
      builder: (context, snap) {
        final data = snap.data;
        final loading = snap.connectionState == ConnectionState.waiting;
        return LargeTitlePage(
          title: data == null ? '위험구역' : data.isHere ? '내 위치 주변' : '성남시 위험구역',
          subtitle: data == null
              ? '불러오는 중'
              : data.isHere
                  ? '현재 위치에서 ${radiusLabel(data.radius)} 안'
                  : data.locationError ?? '성남시 예시 데이터',
          trailing: loading ? const CupertinoActivityIndicator() : null,
          onRefresh: app.refreshMap,
          children: [
            if (data != null) ...[
              if (snap.hasError) EmptyCard('${snap.error}\n이전 결과를 보여 주고 있습니다. 아래로 당겨 다시 시도하세요.'),
              _SearchBar(data),
              _Kpis(data),
              const SizedBox(height: 12),
              ..._content(data),
            ] else if (snap.hasError) ...[
              EmptyCard('${snap.error}\n서버 연결을 확인해 주세요.'),
              Center(child: CupertinoButton(onPressed: app.reloadMap, child: const Text('다시 시도'))),
            ] else
              const Padding(padding: EdgeInsets.all(40), child: CupertinoActivityIndicator()),
          ],
        );
      },
    ),
  );

  // 현재 화면 값에서 출발: 움직이는 중에 다른 곳을 눌러도 끊기지 않음
  void _flyTo(LatLng to, double zoom) {
    if (MediaQuery.disableAnimationsOf(context)) {
      map.move(to, zoom);
      return;
    }
    final from = map.camera;
    final fly = this.fly ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    final t = CurvedAnimation(parent: fly, curve: Curves.easeOutCubic);
    if (flyStep != null) fly.removeListener(flyStep!);
    flyStep = () => map.move(
      LatLng(lerpDouble(from.center.latitude, to.latitude, t.value)!, lerpDouble(from.center.longitude, to.longitude, t.value)!),
      lerpDouble(from.zoom, zoom, t.value)!,
    );
    fly
      ..addListener(flyStep!)
      ..forward(from: 0);
  }

  // 구역을 고르면 지도에서 표시하고 상세 시트를 띄움 (목록 아래쪽에서 눌러도 바로 보이게)
  void _open(Map<String, dynamic>? zone, MapData data, {double? zoom}) {
    if (zone == null) return;
    setState(() => selected = zone['riskZoneId']);
    if (zoom != null) _flyTo(LatLng(zone['latitude'], zone['longitude']), zoom);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _ZoneDetail(zone: zone, events: data.events.where((e) => zoneOf(e, data.zones)?['riskZoneId'] == zone['riskZoneId']).length),
        ),
      ),
    );
  }

  List<Widget> _content(MapData data) {
    LatLng at(Map p) => LatLng(p['latitude'], p['longitude']);
    num score(Map z) => z['riskScore'];
    final zones = [...data.zones]..sort((a, b) => score(a).compareTo(score(b))); // 진한 마커가 위로
    final ranked = zones.reversed.toList();
    final sel = ranked.where((z) => z['riskZoneId'] == selected).firstOrNull ?? ranked.firstOrNull;
    final center = LatLng(data.center.latitude, data.center.longitude);
    final dLat = data.radius / 111320, dLng = dLat / math.max(.01, math.cos(data.center.latitude * math.pi / 180));
    final circle = LatLngBounds(LatLng(center.latitude - dLat, center.longitude - dLng), LatLng(center.latitude + dLat, center.longitude + dLng));
    final fit = data.isHere || zones.isEmpty
        ? CameraFit.bounds(bounds: circle, padding: const EdgeInsets.all(12))
        : CameraFit.coordinates(coordinates: zones.map(at).toList(), padding: const EdgeInsets.all(30));
    // 검색 기준이 바뀌면 카메라도 이동 (initialCameraFit 은 처음 한 번만 적용됨)
    final fitKey = '${data.center}-${data.radius}';
    if (fittedTo != fitKey) {
      if (fittedTo != null) WidgetsBinding.instance.addPostFrameCallback((_) => map.fitCamera(fit));
      fittedTo = fitKey;
    }

    return [
      AppCard(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * .5, 420),
          child: Stack(
            children: [
              FlutterMap(
                mapController: map,
                options: MapOptions(
                  initialCameraFit: fit,
                  keepAlive: true, // 스크롤로 벗어나도 카메라·타일 유지
                  backgroundColor: bg,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.bmwyoung.pedestrian_alert',
                    tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _mapTone, child: tile),
                  ),
                  CircleLayer(
                    circles: [
                      if (data.isHere)
                        CircleMarker(
                          point: center,
                          radius: data.radius.toDouble(),
                          useRadiusInMeter: true,
                          color: brand.withValues(alpha: .05),
                          borderColor: brand.withValues(alpha: .5),
                          borderStrokeWidth: 1.5,
                        ),
                      for (final b in data.bursts)
                        CircleMarker(point: at(b), radius: 28, color: brand.withValues(alpha: .1), borderColor: textColor, borderStrokeWidth: 2),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final e in data.recent)
                        Marker(
                          point: at(e),
                          width: 8,
                          height: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: levelColors[e['alertLevel']] ?? line,
                              border: Border.all(color: surface),
                            ),
                          ),
                        ),
                      for (final z in zones)
                        Marker(
                          point: at(z),
                          width: 16 + score(z) / 8,
                          height: 16 + score(z) / 8,
                          child: GestureDetector(
                            onTap: () => _open(z, data),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: riskColor(score(z)),
                                border: Border.all(color: z == sel ? textColor : surface, width: z == sel ? 3 : 2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final b in data.bursts)
                        Marker(
                          point: at(b),
                          width: 96,
                          height: 24,
                          child: Transform.translate(
                            offset: const Offset(0, -40),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                '동시 다발 ${b['count']}건',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      if (data.isHere)
                        Marker(
                          point: center,
                          width: 18,
                          height: 18,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: brand,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 5)],
                            ),
                          ),
                        ),
                      // 선택한 구역 말풍선 (웹의 툴팁)
                      if (sel != null)
                        Marker(
                          point: at(sel),
                          width: 150,
                          height: 44,
                          child: Transform.translate(
                            offset: const Offset(0, -36),
                            child: GestureDetector(
                              onTap: () => _open(sel, data),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2))],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${sel['name']}', style: bold.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${sel['riskScore']}점 · ${sel['riskLevel']}', style: TextStyle(color: textColor, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                right: 6,
                bottom: 4,
                child: Text('© OpenStreetMap contributors', style: TextStyle(color: textColor, fontSize: 10, shadows: [Shadow(color: surface, blurRadius: 4)])),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Frosted(
                  radius: 12,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('낮음 ', style: bold.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                        Container(
                          width: 48,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(colors: [for (final (_, c) in ramp) c], stops: [for (final (v, _) in ramp) v / 100]),
                          ),
                        ),
                        Text(' 높음  ', style: bold.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: textColor, width: 2)),
                        ),
                        Text(' 동시 다발', style: bold.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      DashCard(
        title: '동시 다발 구역',
        trailing: Text(data.burstRule, style: smallMuted),
        child: data.bursts.isEmpty
            ? Text('현재 기준에 해당하는 구역이 없습니다', style: smallMuted)
            : Column(
                children: [
                  for (final b in data.bursts)
                    Pressable(
                      onTap: () {
                        _flyTo(at(b), 16);
                        _open(data.zones.where((z) => z['name'] == b['zone']).firstOrNull, data);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(10)),
                              child: Text('${b['count']}건', style: TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 13, fontFeatures: _tabular)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${b['zone']}', style: bold),
                                  Text('${b['start'].substring(11, 16)}–${b['end'].substring(11, 16)}', style: smallMuted),
                                ],
                              ),
                            ),
                            Icon(CupertinoIcons.chevron_forward, size: 16, color: muted),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (sel == null)
        EmptyCard('주변 ${radiusLabel(data.radius)} 안에 등록된 위험구역이 없습니다. 반경을 넓히거나 성남시 예시를 확인해 보세요.')
      else
        DashCard(
          title: '위험구역 위험도',
          trailing: Text('0–100점', style: smallMuted),
          child: Column(
            children: [
              for (final z in ranked)
                Pressable(
                  onTap: () => _open(z, data, zoom: 15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(width: 118, child: Text('${z['name']}', style: TextStyle(color: textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: score(z) / 100,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: riskColor(score(z)),
                            backgroundColor: line,
                          ),
                        ),
                        SizedBox(
                          width: 42,
                          child: Text('${score(z)}', textAlign: TextAlign.right, style: bold.copyWith(fontSize: 13, fontFeatures: _tabular)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (data.events.isNotEmpty) ...[
        DashCard(title: '시간대별 감지 건수', trailing: Text('경고 단계별', style: smallMuted), child: _AlertsByHour(data.events)),
        DashCard(
          title: '차량 접근 이벤트',
          trailing: Text('주변 ${data.events.length}건 · 최근 ${AppState.eventScan}건 기준', style: smallMuted),
          child: Column(
            children: [
              for (final (i, e) in data.events.indexed) ...[
                if (i > 0) Divider(height: 1, color: line),
                Pressable(
                  onTap: () => _open(zoneOf(e, data.zones), data, zoom: 15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${zoneOf(e, data.zones)?['name'] ?? '구역 밖'}', style: bold),
                              const SizedBox(height: 2),
                              Text(
                                '${e['startedAt'].replaceAll('T', ' ').substring(0, 16)} · ${e['minEstimatedDistance']}m · 진동 ${e['vibrationTriggered'] == true ? '작동' : '없음'}',
                                style: mutedText.copyWith(fontFeatures: _tabular),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LevelBadge('${e['alertLevel']}'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      _myAlertsChart(),
    ];
  }

  // 앱에서 받은 경고(테스트 포함) 위치의 구역 위험도 기록
  Widget _myAlertsChart() {
    final located = app.alerts.reversed.where((a) => a.zone != null).toList();
    if (located.isEmpty) {
      return const EmptyCard('내 경고 기록: 위험구역 근처에서 경고를 받으면 구역 위험도가 여기에 쌓입니다.');
    }
    return DashCard(
      title: '내 경고 기록',
      trailing: Text('경고 ${located.length}건 위치의 구역 위험도', style: smallMuted),
      child: SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minX: 1,
            maxX: located.length.toDouble().clamp(2, double.infinity),
            minY: 0,
            maxY: 100,
            borderData: FlBorderData(show: false),
            gridData: _grid(25),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: _leftTitles(25),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: ((located.length - 1) / 5).ceilToDouble().clamp(1, double.infinity),
                  getTitlesWidget: (x, _) => Text(
                    x == x.roundToDouble() && x >= 1 && x <= located.length ? hhmmss(located[x.toInt() - 1].time).substring(0, 5) : '',
                    style: axisStyle,
                  ),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => ink,
                getTooltipItems: (touched) => [
                  for (final s in touched)
                    LineTooltipItem(
                      '${hhmmss(located[s.x.toInt() - 1].time)} · ${s.y}점',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final (i, a) in located.indexed) FlSpot(i + 1, (a.zone!['riskScore'] as num).toDouble())],
                preventCurveOverShooting: true,
                isCurved: true,
                color: brand,
                barWidth: 2,
                dotData: FlDotData(
                  getDotPainter: (s, _, _, _) => FlDotCirclePainter(radius: 4.5, color: riskColor(s.y), strokeWidth: 2, strokeColor: surface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

FlGridData _grid(double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) => FlLine(color: line, strokeWidth: 1),
);

AxisTitles _leftTitles(double interval) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 30,
    interval: interval,
    getTitlesWidget: (v, _) => Text('${v.toInt()}', style: axisStyle),
  ),
);

/// 검색 기준: 반경 선택, 내 위치 ↔ 성남시 예시 전환. 반경 표시는 응답을 기다리지 않고 바로 바뀜
class _SearchBar extends StatelessWidget {
  const _SearchBar(this.data);
  final MapData data;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      children: [
        if (data.isHere)
          Expanded(
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: app.searchRadius,
              children: {
                for (final r in searchRadii) r: Text(radiusLabel(r), style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
              },
              onValueChanged: (r) {
                HapticFeedback.selectionClick();
                app.setSearch(radius: r);
              },
            ),
          )
        else
          const Spacer(),
        CupertinoButton(
          padding: const EdgeInsets.only(left: 12),
          minimumSize: const Size(44, 36),
          onPressed: () => app.setSearch(seongnamView: data.isHere),
          child: Text(data.isHere ? '성남시 예시' : '내 위치로', style: const TextStyle(fontSize: 14)),
        ),
      ],
    ),
  );
}

/// KPI 4개 (웹의 .kpis)
class _Kpis extends StatelessWidget {
  const _Kpis(this.data);
  final MapData data;

  @override
  Widget build(BuildContext context) {
    final events = data.events, zones = data.zones;
    final danger = events.where((e) => e['alertLevel'] == 'DANGER').length;
    final high = zones.where((z) => z['riskLevel'] == 'HIGH').length;
    final scores = zones.map((z) => z['riskScore'] as num).toList();
    final avg = scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;
    final top = scores.isEmpty ? null : scores.reduce((a, b) => a > b ? a : b);
    Widget kpi(String k, String v, String s) => Expanded(
      child: AppCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: smallMuted, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(v, style: bold.copyWith(fontSize: 30, height: 1.25, letterSpacing: -.6, fontFeatures: _tabular)),
              Text(s, style: smallMuted, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              kpi(
                data.isHere ? '주변 접근 이벤트' : '접근 이벤트',
                '${events.length}',
                events.isEmpty ? '기록 없음' : '최근 ${events.first['startedAt'].substring(5, 16).replaceAll('T', ' ')}',
              ),
              const SizedBox(width: 12),
              kpi('DANGER 경고', '$danger', '이벤트 ${events.length}건 중'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              kpi('HIGH 위험구역', '$high', '${data.isHere ? '주변' : '전체'} ${zones.length}곳'),
              const SizedBox(width: 12),
              kpi('평균 구역 위험도', zones.isEmpty ? '–' : avg.toStringAsFixed(1), top == null ? '구역 없음' : '최고 $top점'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 위험구역 상세 시트 (GET /risk-zones/{id}): 목록 값으로 먼저 그려 시트 높이가 튀지 않게 하고, 모델 버전·출처를 채움
class _ZoneDetail extends StatefulWidget {
  const _ZoneDetail({required this.zone, required this.events});
  final Map<String, dynamic> zone;
  final int events;

  @override
  State<_ZoneDetail> createState() => _ZoneDetailState();
}

class _ZoneDetailState extends State<_ZoneDetail> {
  late final Future<dynamic> detail = api('/api/v1/risk-zones/${widget.zone['riskZoneId']}');

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: detail,
    builder: (context, snap) {
      final z = snap.data ?? widget.zone;
      Widget row(String k, String v) => Column(
        children: [
          Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: smallMuted.copyWith(fontSize: 14)),
                const SizedBox(width: 16),
                Expanded(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontSize: 14, color: textColor, fontFeatures: _tabular))),
              ],
            ),
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScoreRing(z['riskScore'], size: 56, stroke: 5, fontSize: 15),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${z['name']}', style: bold.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.3)),
                    const SizedBox(height: 2),
                    LevelBadge('${z['riskLevel']}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          row('누적 사고', '${z['accidentCount']}건'),
          row('반경', '${z['radius']}m'),
          row('감지', '${widget.events}건'),
          row('위험도 산출', '${z['modelVersion'] ?? '–'}'),
          row('갱신', '${z['updatedAt'] ?? '–'}'.replaceAll('T', ' ')),
          row('데이터 출처', '한국도로교통공단 사고다발지역'),
        ],
      );
    },
  );
}

/// 시간대별 감지 건수: CAUTION·DANGER 누적 막대
class _AlertsByHour extends StatelessWidget {
  const _AlertsByHour(this.events);
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    int hour(Map e) => int.parse(e['startedAt'].substring(11, 13));
    final hours = {for (final e in events) hour(e)}.toList()..sort();
    int count(int h, String level) => events.where((e) => hour(e) == h && e['alertLevel'] == level).length;
    final caution = levelColors['CAUTION']!, danger = levelColors['DANGER']!;
    final peak = hours.fold(1, (a, h) => a > count(h, 'CAUTION') + count(h, 'DANGER') ? a : count(h, 'CAUTION') + count(h, 'DANGER'));
    Widget key(String label, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(width: 12),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [key('CAUTION', caution), key('DANGER', danger)]),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: peak.toDouble(),
              borderData: FlBorderData(show: false),
              gridData: _grid(1),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: _leftTitles(1),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(hours.length > 12 && v.toInt().isOdd ? '' : '${hours[v.toInt()]}시', style: TextStyle(color: muted, fontSize: 10)),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => ink,
                  fitInsideHorizontally: true,
                  getTooltipItem: (group, _, _, _) {
                    final h = hours[group.x];
                    return BarTooltipItem(
                      '$h시\nCAUTION ${count(h, 'CAUTION')} · DANGER ${count(h, 'DANGER')}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final (i, h) in hours.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (count(h, 'CAUTION') + count(h, 'DANGER')).toDouble(),
                        width: 12,
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        rodStackItems: [
                          BarChartRodStackItem(0, count(h, 'CAUTION').toDouble(), caution),
                          BarChartRodStackItem(count(h, 'CAUTION').toDouble(), (count(h, 'CAUTION') + count(h, 'DANGER')).toDouble(), danger),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
