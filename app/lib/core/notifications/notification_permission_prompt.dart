import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/dio_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'notification_service.dart';

/// 알림 권한 요청 여부를 저장하는 shared_preferences 키(1회만 노출).
const String _kPermissionAskedFlag = 'fcm_permission_asked';

/// 로그인 후 캘린더 첫 진입 시 알림 권한 요청 바텀시트를 **1회만** 띄운다.
///
/// - 이미 물어봤으면(플래그 set) 즉시 반환.
/// - '허용' → 플래그 저장 후 OS 권한 요청, 승인 시 FCM 토큰 등록.
/// - '나중에' → 플래그만 저장(다음부터 안 물음).
///
/// 어느 경로든 실패해도 앱 흐름을 막지 않는다.
Future<void> maybeAskNotificationPermission(
  BuildContext context,
  WidgetRef ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kPermissionAskedFlag) ?? false) return;
  if (!context.mounted) return;

  final accepted = await _showPermissionSheet(context);
  // 결과와 무관하게 "물어봤음"으로 기록(다시 띄우지 않음).
  await prefs.setBool(_kPermissionAskedFlag, true);

  if (accepted == true) {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermission();
    if (granted) {
      await service.registerToken(ref.read(dioProvider));
    }
  }
}

/// 허용/나중에 선택 바텀시트. 허용 시 true, 나중에/닫힘 시 false/null.
Future<bool?> _showPermissionSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
    ),
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 감정/알림 맥락 아이콘 — accent 톤.
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '알림을 받아볼까요?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'PoorStory',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '작심삼일 리마인더와 성공·실패 소식을\n놓치지 않도록 알려드려요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.inkAlt,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // 허용 — 주 CTA(primary).
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.buttonBorderRadius,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  '알림 허용',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 나중에 — 보조 액션.
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  '나중에',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: AppColors.inkAlt,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
