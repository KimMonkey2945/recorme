import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../../core/theme/app_colors.dart';

/// 에디터·상세 본문에 적용하는 '종이 + 명조(serif)' 기본 스타일.
///
/// 기본 [DefaultStyles]는 에디터가 내부에서 머지하므로, 여기서는 문단(paragraph)
/// 스타일만 명조(NanumMyeongjo)·17px·행간 2.0으로 덮어쓴 부분 [DefaultStyles]를
/// 반환한다(나머지 블록 스타일은 기본값 유지). [color]로 감정 텍스트색을 주입할 수 있다.
///
/// 작성(에디터)·열람(상세) 양쪽에서 공용으로 호출해 본문 질감을 일치시킨다.
DefaultStyles diaryPaperStyles(BuildContext context, {Color? color}) {
  final base = DefaultStyles.getInstance(context);
  final paragraph = base.paragraph!;
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
      TextStyle(
        fontFamily: 'PoorStory',
        fontSize: 17,
        height: 2.0,
        color: color ?? AppColors.ink,
      ),
      paragraph.horizontalSpacing,
      paragraph.verticalSpacing,
      paragraph.lineSpacing,
      paragraph.decoration,
    ),
  );
}
