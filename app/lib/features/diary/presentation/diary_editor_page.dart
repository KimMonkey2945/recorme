import 'package:flutter/material.dart';

/// 일기 작성/수정 화면 골격. 선택 날짜(date)는 쿼리 파라미터로 전달.
/// 실제 입력/저장(upsert)은 Phase 2(Task 006)·Phase 3(Task 011).
class DiaryEditorPage extends StatelessWidget {
  const DiaryEditorPage({super.key, this.date});

  /// YYYY-MM-DD. null이면 오늘 날짜로 신규 작성.
  final String? date;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(date == null ? '오늘 기록' : '$date 기록')),
      body: const Center(child: Text('일기 작성 (예정)')),
    );
  }
}
