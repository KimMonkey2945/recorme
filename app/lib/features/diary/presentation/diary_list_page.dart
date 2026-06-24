import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../data/dto/diary_dto.dart';
import 'providers/diary_providers.dart';
import 'widgets/diary_list_tile.dart';

const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 일기 목록 화면.
///
/// 커서 기반 무한 스크롤(더미)로 날짜 역순 목록을 보여준다. 표현은
/// [DiaryListTile], 페이지네이션/상태 관리는 이 래퍼가 담당.
class DiaryListPage extends ConsumerStatefulWidget {
  const DiaryListPage({super.key});

  @override
  ConsumerState<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends ConsumerState<DiaryListPage> {
  final ScrollController _scroll = ScrollController();
  final List<Diary> _items = [];
  int? _cursor;
  bool _hasNext = true;
  bool _loading = false;
  bool _initialLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(diaryRepositoryProvider)
          .getList(cursor: _cursor, size: 20);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasNext = page.hasNext;
        _initialLoading = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _initialLoading = false;
        _loading = false;
      });
    }
  }

  /// 당겨서 새로고침 / 상세에서 돌아온 뒤 재로드.
  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _cursor = null;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  String _dateText(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('목록'),
          actions: [
            IconButton(
              tooltip: '로그아웃',
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) return const LoadingView();
    if (_error != null && _items.isEmpty) {
      return ErrorView(message: '목록을 불러오지 못했어요', onRetry: _refresh);
    }
    if (_items.isEmpty) {
      return const EmptyStateView(
        icon: Icons.book_outlined,
        message: '아직 작성한 일기가 없어요',
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _items.length + (_hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          // 마지막 칸: 다음 페이지 로딩 인디케이터
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.accent,
                  ),
                ),
              ),
            );
          }
          final diary = _items[index];
          return DiaryListTile(
            dateText: _dateText(diary.writtenDate),
            preview: diary.content,
            onTap: () async {
              await context.push('/diary/${diary.id}');
              if (mounted) _refresh();
            },
          );
        },
      ),
    );
  }
}
