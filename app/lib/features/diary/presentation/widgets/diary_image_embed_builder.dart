import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_colors.dart';

/// 일기 본문 인라인 이미지 임베드 빌더(Quill `image` 타입).
///
/// Delta에는 서버 **상대 경로**(`/files/diaries/...`)가 저장되며, 렌더 시
/// [ApiConfig.resolveImageUrl]로 절대 URL로 변환해 네트워크 이미지로 표시한다.
/// (외부 절대 URL이면 그대로 사용.) 에디터·상세 화면 양쪽에서 공용으로 쓴다.
class DiaryImageEmbedBuilder extends EmbedBuilder {
  const DiaryImageEmbedBuilder({this.maxHeight = 320});

  /// 본문 이미지의 최대 표시 높이.
  final double maxHeight;

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    final url = ApiConfig.resolveImageUrl(data is String ? data : data?.toString());
    if (url == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => Container(
              height: 80,
              alignment: Alignment.center,
              color: AppColors.hairline,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
