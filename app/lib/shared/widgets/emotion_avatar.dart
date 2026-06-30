import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/diary_theme.dart';
import '../../core/theme/emotion_assets.dart';

/// 감정 코드를 마스코트 이미지로 표시하는 재사용 위젯.
///
/// [EmotionAssets]를 단일 진실원으로 삼아 `primaryEmotion` 코드 → 레서판다 표정
/// PNG를 그린다. 유니코드 이모지를 대체하며, 에셋 로드 실패 시 [moodEmoji](유니코드)
/// 로 graceful degrade 한다.
///
/// ## 크기별 자동 적응
/// - [size] >= 24: accent 15% 원형 배경 칩 위에 이미지 (무드 뱃지 스타일, 상세 화면)
/// - [size] < 24: 배경 칩 없이 이미지만 (캘린더·목록 등 작은 셀)
///
/// ## 폴백 (이미지 로드 실패 시)
/// 1. [moodEmoji](전달 시) 텍스트
/// 2. 중립 표정 머티리얼 아이콘
///
/// ## 접근성
/// [semanticLabel]이 null이면 [emotionCode] 기반 한국어 라벨(예: '기쁨')을 자동 부여한다.
/// 부모가 이미 의미를 제공하는 경우(예: 캘린더 날짜 셀) 빈 문자열('')을 넘겨 중복을 막는다.
class EmotionAvatar extends StatelessWidget {
  const EmotionAvatar({
    super.key,
    required this.emotionCode,
    required this.size,
    this.moodEmoji,
    this.backgroundColor,
    this.showShadow = false,
    this.semanticLabel,
  });

  /// 감정 코드 (예: 'JOY', 'SADNESS'). null·미상이면 neutral 이미지.
  final String? emotionCode;

  /// 위젯 전체 크기(dp). 칩이 있으면 이미지는 이 크기의 85%로 표시된다.
  final double size;

  /// 이미지 로드 실패 시 텍스트 폴백 이모지 (예: '😊').
  final String? moodEmoji;

  /// 원형 배경 색상. null이면 [emotionCode]의 accentColor 15% 알파로 자동 결정.
  /// (칩이 표시되는 size >= 24에서만 의미 있음)
  final Color? backgroundColor;

  /// true이면 칩 위에 옅은 드롭 섀도 추가 (size >= 24인 경우에만 적용).
  final bool showShadow;

  /// 접근성 라벨. null이면 [emotionCode] 기반 자동 라벨, ''이면 시맨틱 노드 생략.
  final String? semanticLabel;

  /// 배경 칩을 표시하는 크기 임계값.
  static const double _chipThreshold = 24.0;

  @override
  Widget build(BuildContext context) {
    final bool showChip = size >= _chipThreshold;

    // 칩 배경색 — null이면 DiaryTheme accent에서 자동 결정.
    final Color resolvedBg = backgroundColor ??
        DiaryTheme.fromEmotion(emotionCode).accentColor.withValues(alpha: 0.15);

    // 칩 안에서는 사방 여백을 위해 이미지를 85%로 축소.
    final double imageSize = showChip ? size * 0.85 : size;

    // 시맨틱 라벨: null→자동, ''→없음(부모가 제공)
    final String resolved = semanticLabel ?? EmotionAssets.labelOf(emotionCode);
    final String? imageSemanticLabel = resolved.isEmpty ? null : resolved;

    final Widget image = Image.asset(
      EmotionAssets.assetOf(emotionCode),
      width: imageSize,
      height: imageSize,
      fit: BoxFit.contain, // 캐릭터 손발이 잘리지 않도록
      semanticLabel: imageSemanticLabel,
      errorBuilder: (context, error, stackTrace) => _buildFallback(imageSize),
    );

    // 작은 사이즈: 배경 없이 이미지만
    if (!showChip) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: image),
      );
    }

    // 큰 사이즈: 원형 배경 칩 + 이미지
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: resolvedBg,
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: image,
    );
  }

  /// 이미지 로드 실패 시 폴백: moodEmoji 텍스트 → 중립 아이콘.
  Widget _buildFallback(double imageSize) {
    if (moodEmoji != null && moodEmoji!.isNotEmpty) {
      return Text(
        moodEmoji!,
        style: TextStyle(fontSize: imageSize * 0.7),
        textAlign: TextAlign.center,
      );
    }
    return Icon(
      Icons.sentiment_satisfied_alt_outlined,
      size: imageSize * 0.8,
      color: AppColors.inkMuted,
    );
  }
}
