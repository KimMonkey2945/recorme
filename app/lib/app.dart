import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// 웹·데스크톱에서도 마우스 드래그로 스크롤·스와이프가 되게 하는 스크롤 동작.
///
/// Flutter 기본 [MaterialScrollBehavior]의 `dragDevices`에는 마우스가 빠져 있어,
/// 터치 기기에서는 잘 넘어가는 `PageView`(캐릭터 선택 캐러셀 등)가 웹에서는
/// 마우스로 전혀 끌리지 않는다. 실사용 타깃은 터치(iOS/Android)지만 웹이 상시
/// 개발·확인 경로이므로 마우스·트랙패드를 드래그 장치에 포함한다.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

/// 앱 루트. go_router 라우터와 전역 테마를 연결한다.
class RecordApp extends ConsumerStatefulWidget {
  const RecordApp({super.key});

  @override
  ConsumerState<RecordApp> createState() => _RecordAppState();
}

class _RecordAppState extends ConsumerState<RecordApp> {
  @override
  void initState() {
    super.initState();
    // 알림 서비스 초기화(로컬 알림 채널 등록 + 포그라운드/딥링크 리스너).
    // 인증과 무관하게 앱 시작 시 1회 배선한다. 토큰 등록은 로그인 후 별도 수행.
    ref.read(notificationServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'record',
      theme: AppTheme.light,
      routerConfig: router,
      scrollBehavior: _AppScrollBehavior(),
      debugShowCheckedModeBanner: false,
      // flutter_quill 에디터/툴바가 요구하는 로컬라이제이션 델리게이트 포함.
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
    );
  }
}
