import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 일기 목록 화면 골격. 실제 커서 무한 스크롤은 Phase 2(Task 006)·Phase 3(Task 011).
class DiaryListPage extends StatelessWidget {
  const DiaryListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('목록')),
      body: ListView.builder(
        itemCount: 3,
        itemBuilder: (context, index) => ListTile(
          title: Text('일기 항목 ${index + 1} (예정)'),
          onTap: () => context.push('/diary/${index + 1}'),
        ),
      ),
    );
  }
}
