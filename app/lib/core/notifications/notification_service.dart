import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';
import '../router/app_router.dart';

/// 작심삼일 리마인더/결과 알림을 표시하는 안드로이드 알림 채널.
///
/// 백엔드가 보내는 FCM 메시지의 `android.notification.channel_id`와 일치해야
/// 포그라운드 수동 표시와 동일 채널로 묶인다. 중요도 high로 헤드업 배너 노출.
const AndroidNotificationChannel _resolutionChannel = AndroidNotificationChannel(
  'resolution_reminders',
  '작심삼일 알림',
  description: '작심삼일 리마인더 및 성공/실패 알림',
  importance: Importance.high,
);

/// FCM 푸시 통합 서비스.
///
/// - 로컬 알림 플러그인 초기화(안드로이드 채널 사전 등록)
/// - 포그라운드 메시지 → 로컬 알림으로 표시(같은 채널)
/// - 알림 탭(백그라운드/종료 상태 포함) → `resolutionId` 딥링크
/// - FCM 토큰 등록/해제(`/devices/tokens`)
///
/// Firebase 미초기화(초기화 실패)·권한 거부 상황에서도 크래시 없이 no-op으로
/// 동작하도록 모든 진입점을 가드한다.
class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 현재 실행 플랫폼 코드(백엔드 계약: ANDROID|IOS|WEB).
  /// dart:io Platform 대신 defaultTargetPlatform을 써서 웹에서도 컴파일된다.
  String get _platform {
    if (kIsWeb) return 'WEB';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';
  }

  /// Firebase가 초기화됐는지(초기화 실패 시 false). 메시징 API 호출 전 가드용.
  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  /// 앱 셸에서 1회 호출. 로컬 알림 초기화 + 채널 등록 + 메시지 리스너 배선.
  ///
  /// 인증과 무관하게 앱 시작 시 실행한다(토큰 등록은 별도로 로그인 후 수행).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 웹은 FCM/로컬 알림(flutter_local_notifications 웹 미지원)을 쓰지 않으므로 전체 no-op.
    if (kIsWeb) return;

    // ── 로컬 알림 플러그인 초기화 ──
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS는 권한 요청을 requestPermission()에서 일괄 처리하므로 여기선 요청하지 않는다.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        // 로컬 알림 탭 → payload에 담긴 resolutionId로 딥링크.
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateToResolution(payload);
        }
      },
    );
    // 안드로이드 알림 채널 사전 등록(중복 등록은 멱등).
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_resolutionChannel);

    // Firebase 미초기화면 메시징 리스너를 걸지 않는다(크래시 방지).
    if (!_firebaseReady) return;

    // 포그라운드 수신 → 로컬 알림으로 표시.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    // 백그라운드 상태에서 알림 탭으로 앱 진입.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageNavigation);
    // 종료 상태에서 알림 탭으로 앱이 시작된 경우.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleMessageNavigation(initialMessage);

    // 토큰 갱신 시 백엔드에 재등록.
    FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);
  }

  /// 알림 권한 요청 + iOS 포그라운드 표시 옵션 설정.
  ///
  /// 반환값은 권한 승인 여부. Firebase 미초기화면 false.
  Future<bool> requestPermission() async {
    if (!_firebaseReady) return false;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    // iOS: 앱이 포그라운드일 때도 시스템 배너를 노출하도록 설정.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  /// 현재 FCM 토큰을 백엔드에 등록(`POST /devices/tokens`).
  ///
  /// 로그인(세션 확립) 직후 또는 권한 승인 직후 호출한다. Bearer는
  /// AuthInterceptor가 자동 첨부하므로 세션이 없으면 실패하고 조용히 무시된다.
  Future<void> registerToken(Dio dio) async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _sendToken(token, dio: dio);
    } catch (_) {
      // 토큰 조회/등록 실패는 앱 흐름을 막지 않는다(다음 갱신 시 재시도).
    }
  }

  /// 로그아웃 시 호출. 현재 토큰을 백엔드에서 제거 후 로컬 토큰도 무효화한다.
  ///
  /// 반드시 Supabase signOut **이전**에 호출해 Bearer가 유효할 때 DELETE가 나가게 한다.
  Future<void> unregister(Dio dio) async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await dio.delete(
          '/devices/tokens',
          queryParameters: {'token': token},
        );
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // 해제 실패도 무시(로그아웃 자체는 진행돼야 한다).
    }
  }

  /// 토큰을 백엔드에 등록한다. [dio] 미지정 시 provider에서 읽는다(토큰 갱신 리스너용).
  Future<void> _sendToken(String token, {Dio? dio}) async {
    final Dio client = dio ?? _ref.read(dioProvider);
    try {
      await client.post(
        '/devices/tokens',
        data: {'token': token, 'platform': _platform},
      );
    } catch (_) {
      // 미인증 등으로 실패하면 무시(로그인 후 재등록 경로가 커버).
    }
  }

  /// 포그라운드 메시지를 로컬 알림으로 표시한다.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    // iOS는 setForegroundNotificationPresentationOptions로 시스템이 배너를
    // 표시하므로, 중복 노출을 피하기 위해 안드로이드에서만 수동 표시한다.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _resolutionChannel.id,
          _resolutionChannel.name,
          channelDescription: _resolutionChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      // 탭 시 딥링크에 사용할 resolutionId.
      payload: message.data['resolutionId'],
    );
  }

  /// 알림 데이터의 `resolutionId`가 있으면 상세 화면으로 딥링크한다.
  ///
  /// data 계약: `{type: REMINDER|SUCCESS|FAILED, resolutionId, checkDate?}`.
  void _handleMessageNavigation(RemoteMessage message) {
    final id = message.data['resolutionId'];
    if (id != null && id.isNotEmpty) _navigateToResolution(id);
  }

  /// go_router로 `/resolution/:id` 이동. 라우터 미준비/실패는 조용히 무시.
  void _navigateToResolution(String resolutionId) {
    try {
      _ref.read(routerProvider).push('/resolution/$resolutionId');
    } catch (_) {}
  }
}

/// 앱 전역 알림 서비스 provider.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref),
);
