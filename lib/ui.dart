import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'state.dart';

// 웹(web/index.html)과 같은 디자인 토큰. 화면 모드가 바뀌면 앱 전체를 다시 만들므로(main.dart) 읽을 때 값을 정함
bool get isDark => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
Color get brand => isDark ? const Color(0xFF4A90EE) : const Color(0xFF1C69D4);
Color get brandSoft => isDark ? const Color(0xFF14294A) : const Color(0xFFE8F0FB);
Color get bg => isDark ? Colors.black : const Color(0xFFF5F5F7);
Color get surface => isDark ? const Color(0xFF1C1C1E) : Colors.white;
Color get textColor => isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
Color get muted => isDark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);
Color get line => isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000);
Color get chrome => isDark ? const Color(0xB8000000) : const Color(0xB8F5F5F7); // 내용이 뒤로 지나가는 막대
const ink = Color(0xFF0B1F3A); // 그래프 말풍선
const _low = Color(0xFFF4A07E);
Color get _mid => isDark ? const Color(0xFFEE5C41) : const Color(0xFFE0492F);
Color get _high => isDark ? const Color(0xFFD24B4B) : const Color(0xFF8A1111);
// 위험구역 단계(LOW·MEDIUM·HIGH)와 접근 경고 단계(CAUTION·DANGER)
Map<String, Color> get levelColors => {'LOW': _low, 'MEDIUM': _mid, 'HIGH': _high, 'CAUTION': _low, 'DANGER': _high};
List<(double, Color)> get ramp => [(0.0, const Color(0xFFFDE4D8)), (35.0, _low), (70.0, _mid), (100.0, _high)];

/// 위험도 0~100 → 연한색에서 진한색 (웹 riskColor 와 동일)
Color riskColor(num score) {
  final s = score.clamp(0, 100).toDouble();
  final stops = ramp;
  for (var i = 1; i < stops.length; i++) {
    final (a, ca) = stops[i - 1];
    final (b, cb) = stops[i];
    if (s <= b) return Color.lerp(ca, cb, (s - a) / (b - a))!;
  }
  return stops.last.$2;
}

String hhmmss(DateTime t) => [t.hour, t.minute, t.second].map((v) => '$v'.padLeft(2, '0')).join(':');

TextStyle get bold => TextStyle(fontWeight: FontWeight.w600, color: textColor);
TextStyle get mutedText => TextStyle(color: muted, fontSize: 13, height: 1.4);

/// 큰 제목 화면: 스크롤하면 제목이 접히고 내용은 반투명 막대 뒤로 지나감. 경계선은 겹칠 때만 나타남
class LargeTitlePage extends StatelessWidget {
  const LargeTitlePage({super.key, required this.title, this.subtitle, this.trailing, this.onRefresh, this.bottomGap = 24, required this.children});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final double bottomGap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        CupertinoSliverNavigationBar(largeTitle: Text(title), trailing: trailing, backgroundColor: chrome, transitionBetweenRoutes: false),
        if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + bottomGap),
          sliver: SliverList.list(children: [
            if (subtitle != null)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Text(subtitle!, style: mutedText.copyWith(fontSize: 15))),
            ...children,
          ]),
        ),
      ]);
}

/// 손이 닿는 즉시 눌림 표시, 떼면 동작. 10px 넘게 움직이면 스크롤로 보고 취소. 애니메이션은 현재 값에서 이어져 도중에 뒤집을 수 있음
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child, this.label});
  final VoidCallback? onTap;
  final Widget child;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  Offset start = Offset.zero;

  void _press(bool v) {
    if (v != down) setState(() => down = v);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: widget.onTap != null,
        label: widget.label,
        child: Listener(
          onPointerDown: (e) {
            start = e.position;
            _press(widget.onTap != null);
          },
          onPointerMove: (e) {
            if ((e.position - start).distance > 10) _press(false);
          },
          onPointerUp: (_) => _press(false),
          onPointerCancel: (_) => _press(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: down && !MediaQuery.disableAnimationsOf(context) ? .97 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(opacity: down ? .7 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
            ),
          ),
        ),
      );
}

/// 지도·목록 위에 뜨는 반투명 재질
class Frosted extends StatelessWidget {
  const Frosted({super.key, required this.child, this.radius = 0});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(color: chrome, child: child),
        ),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12)});
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
        child: child,
      );
}

/// 웹의 .card + .card-head: 제목과 오른쪽 작은 설명이 있는 카드
class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.title, this.trailing, required this.child});
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              Text(title, style: bold.copyWith(fontSize: 17, letterSpacing: -.2)),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: bold.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.3), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ?trailing,
        ]),
      );
}

/// 웹의 .lv 와 동일: 색 점 + 글자는 본문색
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key});
  final String level;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: levelColors[level] ?? line, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(level, style: bold.copyWith(fontSize: 12)),
      ]);
}

/// 위험도 고리. 값이 바뀌면 지금 값에서 이어서 움직임
class ScoreRing extends StatelessWidget {
  const ScoreRing(this.score, {super.key, this.size = 44, this.stroke = 4, this.fontSize = 13, this.pending = false});
  final num? score;
  final double size, stroke, fontSize;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final score = this.score;
    return SizedBox.square(
      dimension: size,
      child: Stack(fit: StackFit.expand, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: (score ?? 0) / 100),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => CircularProgressIndicator(
            value: pending ? null : v,
            strokeWidth: stroke,
            strokeCap: StrokeCap.round,
            strokeAlign: CircularProgressIndicator.strokeAlignInside,
            backgroundColor: line,
            color: score == null ? brand : riskColor(score),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(stroke + 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              score == null ? '–' : '$score',
              style: bold.copyWith(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -.3, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ]),
    );
  }
}

class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: brandSoft, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: brand, size: 20),
      );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      AppCard(child: Padding(padding: const EdgeInsets.all(18), child: Text(text, style: mutedText)));
}

class AlertCard extends StatelessWidget {
  const AlertCard(this.a, {super.key});
  final Alert a;

  @override
  Widget build(BuildContext context) {
    final zone = a.zone;
    final score = zone?['riskScore'] as num?;
    final e = a.event;
    final note = a.error ??
        (zone != null
            ? '${zone['name']} ${zone['distance']}m · 위험도 ${zone['riskLevel']}'
            : a.checkedZones
                ? '주변 $nearbyRadiusM m 안에 등록된 위험구역 없음'
                : '감지 기록 저장 중...');
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                LevelBadge(e['alert_level'] == 'DANGER' ? 'DANGER' : 'CAUTION'),
                const SizedBox(width: 8),
                Text(hhmmss(a.time), style: TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Text('거리 ${e['min_estimated_distance']}m · RSSI ${e['max_rssi']}dBm · 연속 ${e['consecutive_count']}회', style: bold),
              const SizedBox(height: 2),
              Text(note, style: mutedText),
            ]),
          ),
          if (score != null) ...[const SizedBox(width: 12), ScoreRing(score)],
        ]),
      ),
    );
  }
}
