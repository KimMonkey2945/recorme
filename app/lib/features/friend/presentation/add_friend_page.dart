import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import 'providers/friend_providers.dart';
import 'widgets/friend_code_card.dart';
import 'widgets/search_result_tile.dart';

/// 친구 추가 화면(/friends/add). 내 친구코드 공유 + 코드 입력 + 닉네임 검색.
class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({super.key});

  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  final _codeController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _codeController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    await _request(() => ref.read(friendRepositoryProvider).requestByCode(code));
    _codeController.clear();
  }

  Future<void> _addByUuid(String uuid) =>
      _request(() => ref.read(friendRepositoryProvider).requestByUuid(uuid));

  /// 요청 전송 공통 처리(자동 수락 여부에 따라 안내 분기 + 관련 provider 갱신).
  Future<void> _request(Future<dynamic> Function() action) async {
    try {
      final result = await action();
      ref.invalidate(outgoingRequestsProvider);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(friendsProvider);
      if (_query.isNotEmpty) ref.invalidate(friendSearchProvider(_query));
      if (!mounted) return;
      final accepted = result?.autoAccepted == true;
      showAppSnackBar(context, accepted ? '친구가 되었어요' : '친구 요청을 보냈어요');
    } on Failure catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final myCode = profileAsync.asData?.value.friendCode;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('친구 추가'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FriendCodeCard(code: myCode),
                const SizedBox(height: AppSpacing.xl),

                // ── 코드로 추가 ──
                const _SectionLabel('코드로 추가'),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          UpperCaseFormatter(),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          hintText: '친구 코드 입력',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        onSubmitted: (_) => _submitCode(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _submitCode,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.surface,
                      ),
                      child: const Text('추가'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── 닉네임으로 검색 ──
                const _SectionLabel('닉네임으로 검색'),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  decoration: const InputDecoration(
                    hintText: '닉네임 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildSearchResults(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_query.isEmpty) return const SizedBox.shrink();
    final async = ref.watch(friendSearchProvider(_query));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      ),
      error: (e, _) => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text('검색에 실패했어요',
            style: TextStyle(color: AppColors.error)),
      ),
      data: (results) {
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('검색 결과가 없어요',
                style: TextStyle(color: AppColors.inkMuted)),
          );
        }
        return Column(
          children: [
            for (final r in results) ...[
              SearchResultTile(
                result: r,
                onAdd: () => _addByUuid(r.userUuid),
                onAccept: () => _addByUuid(r.userUuid),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

/// 섹션 라벨(작은 회색 헤더).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.inkMuted,
        ),
      );
}

/// 친구코드 입력을 대문자로 강제(저장이 대문자 캐노니컬이라 UX 일관).
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
