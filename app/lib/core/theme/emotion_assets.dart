/// 감정(primaryEmotion) 기반 마스코트 이미지 에셋 경로 매핑.
///
/// AI가 분류한 감정 코드를 받아 레서판다 마스코트의 표정 PNG 경로를 반환한다.
/// 색 팔레트([DiaryTheme])와 동일하게, 시각 표현은 LLM/DB 값이 아니라 감정 코드를
/// 기준으로 클라이언트에서 결정론적으로 매핑한다.
///
/// ## 단일 진실원
/// 모든 감정 이미지 경로·한국어 라벨은 여기서만 정의한다.
/// [DiaryTheme]의 `_palette`와 동일한 별칭(HAPPY/SAD 등)을 지원하며,
/// null·미상 코드는 [neutral]로 폴백한다.
///
/// ## 에셋 위치
/// `app/assets/emotions/*.png` — 투명배경 레서판다 마스코트.
/// (원본: docs/recormeImo/imo/ — carm.png는 calm.png로 리네임 후 복사)
class EmotionAssets {
  EmotionAssets._();

  // ─── 에셋 경로 상수 ─────────────────────────────────────────
  static const String joy = 'assets/emotions/joy.png';
  static const String sadness = 'assets/emotions/sadness.png';
  static const String anger = 'assets/emotions/anger.png';
  static const String calm = 'assets/emotions/calm.png'; // 원본 carm.png → 리네임
  static const String anxiety = 'assets/emotions/anxiety.png';
  static const String neutral = 'assets/emotions/neutral.png'; // 폴백용

  // ─── 영상(mp4) 에셋 경로 상수 ────────────────────────────────
  // 움직이는 마스코트. 알파 매트 패킹 mp4([좌: 색 | 우: 실루엣 알파], 2:1)로,
  // 앱 프래그먼트 셰이더가 배경을 투명 처리해 캐릭터만 렌더한다(EmotionVideo).
  // PNG는 영상 로딩 전·실패 시(및 웹) 포스터/폴백으로 쓰인다.
  static const String joyVideo = 'assets/emotions/video/packed/joy.mp4';
  static const String sadnessVideo = 'assets/emotions/video/packed/sadness.mp4';
  static const String angerVideo = 'assets/emotions/video/packed/anger.mp4';
  static const String calmVideo = 'assets/emotions/video/packed/calm.mp4';
  static const String anxietyVideo = 'assets/emotions/video/packed/anxiety.mp4';
  static const String neutralVideo = 'assets/emotions/video/packed/neutral.mp4'; // 폴백용

  // ─── 룩업 맵 ────────────────────────────────────────────────

  /// primaryEmotion 코드(대문자) → 에셋 경로 맵.
  /// [DiaryTheme]의 팔레트와 동일한 키셋(별칭 포함)을 유지한다.
  static const Map<String, String> _assetMap = {
    'JOY': joy,
    'HAPPY': joy, // LLM 별칭
    'SADNESS': sadness,
    'SAD': sadness,
    'ANGER': anger,
    'ANGRY': anger,
    'CALM': calm,
    'PEACEFUL': calm,
    'ANXIETY': anxiety,
    'ANXIOUS': anxiety,
    'NEUTRAL': neutral,
  };

  /// primaryEmotion 코드(대문자) → 영상 경로 맵.
  /// [_assetMap]과 동일한 키셋(별칭 포함)을 유지한다.
  static const Map<String, String> _videoMap = {
    'JOY': joyVideo,
    'HAPPY': joyVideo,
    'SADNESS': sadnessVideo,
    'SAD': sadnessVideo,
    'ANGER': angerVideo,
    'ANGRY': angerVideo,
    'CALM': calmVideo,
    'PEACEFUL': calmVideo,
    'ANXIETY': anxietyVideo,
    'ANXIOUS': anxietyVideo,
    'NEUTRAL': neutralVideo,
  };

  /// [emotionCode](대소문자 무관)로 마스코트 에셋 경로를 반환한다.
  /// null이거나 매핑에 없는 코드는 [neutral]로 폴백한다.
  static String assetOf(String? emotionCode) =>
      _assetMap[emotionCode?.toUpperCase()] ?? neutral;

  /// [emotionCode](대소문자 무관)로 마스코트 영상(mp4) 경로를 반환한다.
  /// null이거나 매핑에 없는 코드는 [neutralVideo]로 폴백한다.
  static String videoOf(String? emotionCode) =>
      _videoMap[emotionCode?.toUpperCase()] ?? neutralVideo;

  /// [emotionCode]에 대응하는 한국어 감정명(접근성 라벨용).
  /// 미상 코드는 '감정'으로 폴백한다.
  static String labelOf(String? emotionCode) =>
      switch (emotionCode?.toUpperCase()) {
        'JOY' || 'HAPPY' => '기쁨',
        'SADNESS' || 'SAD' => '슬픔',
        'ANGER' || 'ANGRY' => '분노',
        'CALM' || 'PEACEFUL' => '평온',
        'ANXIETY' || 'ANXIOUS' => '불안',
        'NEUTRAL' => '중립',
        _ => '감정',
      };
}
