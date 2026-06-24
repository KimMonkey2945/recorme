/// Supabase 연결 설정.
///
/// - url / anonKey: 신규 record 프로젝트(wcrlawgpmwxyxohwlegc).
///   anon(publishable) 키는 클라이언트에 노출돼도 안전하다(데이터 보호는 RLS가 담당).
/// - googleWebClientId / googleIosClientId: Google Cloud Console에서 발급한 OAuth 클라이언트 ID.
///   (Android는 SHA-1만 콘솔에 등록하면 되고 코드엔 web client id만 있으면 된다.)
/// - oauthRedirect: 카카오 등 웹 OAuth 콜백 딥링크. Android/iOS에 스킴 등록됨.
///
/// 값은 `--dart-define`로 주입하거나 아래 defaultValue에 직접 채운다.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://wcrlawgpmwxyxohwlegc.supabase.co';

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indjcmxhd2dwbXd4eXhvaHdsZWdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIyMzI0MTUsImV4cCI6MjA5NzgwODQxNX0.bTSYi_volpQ0IWf3TKMuD_CuR-JnKhTUSNp42W5ZoPY',
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '579893667013-derdbg8docrgu5vm12v7vr5dj6t4faef.apps.googleusercontent.com',
  );

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '579893667013-13k2qqetprqglocaf441bctfuios7nhs.apps.googleusercontent.com',
  );

  /// 소셜 OAuth 콜백 딥링크 (AndroidManifest / Info.plist에 등록).
  static const String oauthRedirect = 'app.recordapp://login-callback';

  static bool get isConfigured => anonKey != 'PASTE_ANON_KEY' && anonKey.isNotEmpty;
}
