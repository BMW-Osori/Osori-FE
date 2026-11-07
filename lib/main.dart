import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alerts.dart';
import 'chat.dart';
import 'home.dart';
import 'map_tab.dart';
import 'state.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(), // 알림 권한 요청 포함
    ),
  );
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const font = 'Pretendard';
    return MaterialApp(
      key: ValueKey(isDark), // 토큰(ui.dart)이 화면 모드를 읽으므로 모드가 바뀌면 전체를 다시 만듦
      title: '보행자 촉각 경고',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const CupertinoScrollBehavior(), // 안드로이드에서도 끝에서 튕기는 스크롤
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        fontFamily: font,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brand,
          brightness: isDark ? Brightness.dark : Brightness.light,
          primary: brand,
          onPrimary: Colors.white,
          surface: surface,
        ),
        scaffoldBackgroundColor: bg,
        splashFactory: NoSplash.splashFactory, // 물결 대신 Pressable·CupertinoButton 의 눌림 표시
        highlightColor: Colors.transparent,
        dividerColor: line,
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        ),
        cupertinoOverrideTheme: CupertinoThemeData(
          primaryColor: brand,
          primaryContrastingColor: Colors.white,
          barBackgroundColor: chrome,
          scaffoldBackgroundColor: bg,
          textTheme: CupertinoTextThemeData(
            primaryColor: brand,
            textStyle: TextStyle(fontFamily: font, fontSize: 15, color: textColor),
            actionTextStyle: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w500, color: brand),
            actionSmallTextStyle: TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w500, color: brand),
            tabLabelTextStyle: TextStyle(fontFamily: font, fontSize: 10, fontWeight: FontWeight.w500, color: muted),
            navTitleTextStyle: TextStyle(fontFamily: font, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -.2, color: textColor),
            navLargeTitleTextStyle: TextStyle(fontFamily: font, fontSize: 34, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -.75, color: textColor),
          ),
        ),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBody: true, // 내용이 반투명 탭 막대 뒤로 지나감
        body: IndexedStack(index: index, children: const [HomeTab(), MapTab(), ChatTab(), AlertsTab()]),
        floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation, // 탭을 오갈 때마다 튀어나오지 않게
        floatingActionButton: index == 0 || index == 3
            ? Pressable(
                onTap: app.testAlert,
                label: '테스트 경고',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.vibration, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('테스트 경고', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ]),
                ),
              )
            : null,
        bottomNavigationBar: ListenableBuilder(
          listenable: app,
          builder: (context, _) => CupertinoTabBar(
            currentIndex: index,
            activeColor: brand,
            inactiveColor: muted,
            backgroundColor: chrome,
            iconSize: 24,
            onTap: (i) {
              HapticFeedback.selectionClick();
              setState(() => index = i);
            },
            items: [ // 글자는 숨겼으므로 이름은 음성 안내(semanticLabel)로만 제공
              const BottomNavigationBarItem(icon: Icon(CupertinoIcons.house, semanticLabel: '홈'), activeIcon: Icon(CupertinoIcons.house_fill, semanticLabel: '홈')),
              const BottomNavigationBarItem(icon: Icon(CupertinoIcons.map, semanticLabel: '지도'), activeIcon: Icon(CupertinoIcons.map_fill, semanticLabel: '지도')),
              const BottomNavigationBarItem(icon: Icon(CupertinoIcons.chat_bubble, semanticLabel: 'AI 채팅'), activeIcon: Icon(CupertinoIcons.chat_bubble_fill, semanticLabel: 'AI 채팅')),
              BottomNavigationBarItem(
                icon: Badge(isLabelVisible: app.recent.isNotEmpty, label: Text('${app.recent.length}'), child: const Icon(CupertinoIcons.bell, semanticLabel: '알림')),
                activeIcon: Badge(isLabelVisible: app.recent.isNotEmpty, label: Text('${app.recent.length}'), child: const Icon(CupertinoIcons.bell_fill, semanticLabel: '알림')),
              ),
            ],
          ),
        ),
      );
}
