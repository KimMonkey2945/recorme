/// 감정 프리셋·한국어 라벨 단일 정의처(Task 024/025 — 감정 사용자 직접 입력).
///
/// LLM 감정 분석을 제거하고 감정을 **사용자가 직접 선택/입력**하는 순수 메타데이터로 전환하면서,
/// 감정 이미지·영상·동적 테마 매핑(구 `EmotionAssets`/`DiaryTheme`)을 걷어냈다.
/// 여기에는 표시에 필요한 **프리셋 6종 + 한국어 라벨 + 이모지**만 남긴다(색은 [EmotionPalette]).
library;

/// 감정 프리셋 1종. 코드는 백엔드 `emotion_types` 마스터(= `primary_emotion`)와 정합한다.
class EmotionPreset {
  const EmotionPreset(this.code, this.labelKo, this.emoji);

  /// 감정 코드(대문자). 예: 'JOY'. 저장 시 `emotion` 필드로 전송된다.
  final String code;

  /// 한국어 표시 라벨. 예: '기쁨'.
  final String labelKo;

  /// 표시용 이모지. 예: '😊'.
  final String emoji;
}

/// 프리셋 6종(선택지). 백엔드 `emotion_types` 시드(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL)와 1:1.
const List<EmotionPreset> kEmotionPresets = [
  EmotionPreset('JOY', '기쁨', '😊'),
  EmotionPreset('SADNESS', '슬픔', '😢'),
  EmotionPreset('ANGER', '분노', '😠'),
  EmotionPreset('CALM', '평온', '😌'),
  EmotionPreset('ANXIETY', '불안', '😟'),
  EmotionPreset('NEUTRAL', '무던', '🙂'),
];

/// [code](대소문자 무관)에 대응하는 한국어 감정명. 미상/커스텀 코드는 '감정'으로 폴백한다.
String emotionLabelOf(String? code) => switch (code?.toUpperCase()) {
      'JOY' || 'HAPPY' => '기쁨',
      'SADNESS' || 'SAD' => '슬픔',
      'ANGER' || 'ANGRY' => '분노',
      'CALM' || 'PEACEFUL' => '평온',
      'ANXIETY' || 'ANXIOUS' => '불안',
      'NEUTRAL' => '무던',
      _ => '감정',
    };

/// [code]에 대응하는 프리셋 이모지. 프리셋이 아니면(커스텀 라벨 등) null.
String? emotionEmojiOf(String? code) {
  if (code == null) return null;
  final upper = code.toUpperCase();
  for (final p in kEmotionPresets) {
    if (p.code == upper) return p.emoji;
  }
  return null;
}
