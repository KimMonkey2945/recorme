import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 하단 탭(캐릭터/캘린더/작심삼일/친구/프로필) 셸.
/// StatefulShellRoute의 각 브랜치를 IndexedStack으로 유지한다.
///
/// ⚠️ destinations 순서 = 브랜치 순서(app_router.dart) = 탭 인덱스. 한쪽만 바꾸면 어긋난다.
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      // 이미 선택된 탭을 다시 누르면 해당 브랜치의 초기 위치로 복귀
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '캘린더',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: '작심삼일',
          ),
          // 피드는 탭에서 빠지고 친구 목록 앱바로 진입한다(친구 중심 앱이라 친구를 탭으로 승격).
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '친구',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '프로필',
          ),
        ],
      ),
    );
  }
}
