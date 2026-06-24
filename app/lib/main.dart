import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase 초기화(세션 자동 복원). runApp 전에 완료해야 한다.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    // anon public 키. supabase_flutter 2.15+는 publishableKey 파라미터 사용(레거시 anon 키도 허용).
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: RecordApp()));
}
