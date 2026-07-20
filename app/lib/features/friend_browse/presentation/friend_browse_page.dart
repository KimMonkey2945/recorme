import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'tabs/friend_calendar_tab.dart';
import 'tabs/friend_character_tab.dart';
import 'tabs/friend_resolution_tab.dart';

/// 친구 둘러보기 — 그 친구의 recorme를 구경하는 읽기 전용 화면.
///
/// 상단 탭 3개(홈·캘린더·작심삼일)로 오간다. 프로필·피드는 범위 밖이고,
/// **쓰기 진입점(작성·출석·옷장·보상함·체크·로그아웃)은 하나도 없다** — 내 계정이 아니기 때문이다.
/// 애초에 백엔드의 친구 둘러보기 API가 전부 GET 이고 기존 쓰기 API는 모두 본인 principal 로만
/// 대상을 정하므로, 남의 리소스를 바꿀 방법 자체가 존재하지 않는다.
///
/// [TabBarView]는 보이는 탭만 build 하므로 첫 진입 시 요청은 1건만 나간다.
class FriendBrowsePage extends StatelessWidget {
  const FriendBrowsePage({
    super.key,
    required this.userUuid,
    this.nickname,
  });

  /// 대상 친구의 외부 노출 uuid(내부 PK는 앱이 알지 못한다).
  final String userUuid;

  /// 목록에서 넘겨받은 닉네임. 있으면 로딩 없이 앱바 제목을 즉시 띄운다.
  final String? nickname;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(nickname == null ? '친구' : '$nickname님의 recorme'),
            bottom: const TabBar(
              tabs: [
                Tab(text: '홈'),
                Tab(text: '캘린더'),
                Tab(text: '작심삼일'),
              ],
            ),
          ),
          body: SafeArea(
            child: TabBarView(
              children: [
                FriendCharacterTab(userUuid: userUuid),
                FriendCalendarTab(userUuid: userUuid, nickname: nickname),
                FriendResolutionTab(userUuid: userUuid),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
