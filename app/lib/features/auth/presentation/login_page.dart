import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';

/// 로그인 화면. Supabase Auth 기반 카카오/구글 소셜 로그인.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      // 성공 시 onAuthStateChange → 라우터 가드가 메인으로 이동시킨다.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인에 실패했어요: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(authControllerProvider.notifier);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('record',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('하루를 글로 기록하세요'),
              const SizedBox(height: 40),
              if (_loading)
                const CircularProgressIndicator()
              else ...[
                FilledButton(
                  onPressed: () => _run(controller.signInWithKakao),
                  child: const Text('카카오로 시작하기'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _run(controller.signInWithGoogle),
                  child: const Text('구글로 시작하기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
