import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 일기 상세 화면 골격. 실제 조회/수정/삭제는 Phase 2(Task 006)·Phase 3(Task 011).
class DiaryDetailPage extends StatelessWidget {
  const DiaryDetailPage({super.key, required this.diaryId});

  final String diaryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상세'),
        actions: [
          IconButton(
            tooltip: '수정',
            onPressed: () => context.push('/editor'),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: '삭제',
            onPressed: () {}, // Phase 3: 삭제 확인 다이얼로그 + DELETE
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Center(child: Text('일기 #$diaryId 상세 (예정)')),
    );
  }
}
