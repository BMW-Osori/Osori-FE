import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'state.dart';
import 'ui.dart';

/// 기본 알림 기능: 알림 설정 + 전체 경고 기록
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          Widget toggle(String title, String subtitle, bool value, void Function(bool) set) => SwitchListTile.adaptive(
                title: Text(title, style: bold),
                subtitle: Text(subtitle, style: mutedText),
                value: value,
                activeTrackColor: brand,
                onChanged: (v) => app.update(() => set(v)),
              );
          return LargeTitlePage(title: '알림', subtitle: '경고 설정과 전체 기록', bottomGap: 88, children: [
            AppCard(
              child: Column(children: [
                toggle('진동 경고', '차량 접근 시 휴대폰 진동', app.vibrate, (v) => app.vibrate = v),
                Divider(height: 1, indent: 16, color: line),
                toggle('푸시 알림', '앱이 백그라운드여도 알림 표시', app.notify, (v) => app.notify = v),
                Divider(height: 1, indent: 16, color: line),
                toggle('동시 다발 알림', '${burstWindow.inMinutes}분 안에 $burstCount건 이상이면 추가 경고', app.burstNotify,
                    (v) => app.burstNotify = v),
              ]),
            ),
            SectionTitle(
              '경고 기록 ${app.alerts.length}건',
              trailing: app.alerts.isEmpty
                  ? null
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 32),
                      onPressed: () => app.update(app.alerts.clear),
                      child: const Text('모두 지우기'),
                    ),
            ),
            if (app.alerts.isEmpty) const EmptyCard("아직 경고가 없습니다. '테스트 경고'로 알림을 확인해 보세요."),
            for (final a in app.alerts) AlertCard(a),
          ]);
        },
      );
}
