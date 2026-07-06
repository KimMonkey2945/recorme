import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_snackbar.dart';

/// 기록 공유 바텀시트. 링크 복사(Clipboard) / 다른 앱으로 공유(OS 네이티브 시트)를 제공한다.
/// [shareUrl]은 공유 대상의 절대 URL(예: `{apiBaseUrl}/diaries/shared/{token}`).
Future<void> showShareOptionsSheet(
  BuildContext context, {
  required String shareUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modal)),
    ),
    builder: (context) => _ShareOptionsSheet(shareUrl: shareUrl),
  );
}

class _ShareOptionsSheet extends StatelessWidget {
  const _ShareOptionsSheet({required this.shareUrl});

  final String shareUrl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '기록 공유하기',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ActionTile(
              icon: Icons.link,
              label: '링크 복사',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: shareUrl));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  showAppSnackBar(context, '링크를 복사했어요');
                }
              },
            ),
            _ActionTile(
              icon: Icons.ios_share,
              label: '다른 앱으로 공유',
              onTap: () async {
                Navigator.of(context).pop();
                await SharePlus.instance.share(ShareParams(uri: Uri.parse(shareUrl)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
