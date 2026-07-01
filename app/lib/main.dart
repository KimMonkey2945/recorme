import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'firebase_options.dart';

/// FCM 백그라운드/종료 상태 메시지 핸들러(top-level, 별도 isolate에서 실행).
///
/// 별도 isolate라 Firebase를 다시 초기화해야 한다. 알림 표시는 시스템이
/// 처리하므로 여기서는 초기화만 보장한다(데이터 전용 메시지 확장 대비).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화. 실패해도 앱은 계속 뜨도록 가드(FCM만 비활성).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {
    // Firebase 미설정/초기화 실패 시 푸시 없이 앱 정상 동작.
  }

  // Supabase 초기화(세션 자동 복원). runApp 전에 완료해야 한다.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    // anon public 키. supabase_flutter 2.15+는 publishableKey 파라미터 사용(레거시 anon 키도 허용).
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: RecordApp()));
}
