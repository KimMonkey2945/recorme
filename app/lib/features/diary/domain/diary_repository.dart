import 'dart:typed_data';

import '../../../shared/models/cursor_page.dart';
import '../data/dto/diary_dto.dart';

/// 기록 데이터 접근 추상화.
///
/// Phase 2에서는 [FakeDiaryRepository]가 인메모리 더미로 구현하고,
/// Phase 3에서 동일 인터페이스의 `ApiDiaryRepository`(실제 API)로 교체한다.
/// 메서드 시그니처는 `docs/api-contract.md`의 엔드포인트와 1:1로 대응한다.
abstract class DiaryRepository {
  /// 월별 작성 요약(캘린더 dot용). [yearMonth]는 'yyyy-MM' 형식.
  /// GET /diaries/me/summary?yearMonth=
  Future<DiarySummary> getMonthlySummary(String yearMonth);

  /// 특정 날짜의 활성 기록. 없으면 null.
  /// GET /diaries/by-date/{date} (404 → null)
  Future<Diary?> getByDate(DateTime date);

  /// id 기반 단건 조회. 없으면 [Failure]('DIARY_NOT_FOUND').
  /// GET /diaries/{id}
  Future<Diary> getById(int id);

  /// 커서 페이징 목록(id 내림차순). [cursor]가 null이면 첫 페이지.
  /// GET /diaries/me?cursor=&size=
  Future<CursorPage<Diary>> getList({int? cursor, int size});

  /// 해당 월([yearMonth] 'yyyy-MM')의 기록 목록(written_date 역순). 하루 1기록이라 페이징 없이 한 번에.
  /// GET /diaries/me?yearMonth=
  Future<List<Diary>> getMonthList(String yearMonth);

  /// 날짜+내용 upsert(하루 1기록). 같은 날짜가 있으면 UPDATE, 없으면 INSERT.
  ///
  /// [content]는 Quill Delta JSON 문자열(인라인 이미지 포함), [contentText]는
  /// 서식·이미지를 제거한 순수 텍스트(글자수 제한·LLM 입력용)다. 본문에 박힌
  /// 이미지 정합(diary_images 동기화·고아 파일 회수)은 서버가 content를 파싱해 처리한다.
  ///
  /// [confirm]이 false(기본값)이면 임시 저장(DRAFT), true이면 확정한다. 감정 분석이 꺼진(기본)
  /// 상태에서 확정은 즉시 DONE 이 되고, 감정은 사용자가 넣은 [emotion]/[emotionLabel]로 저장된다.
  /// [visibility]는 공개범위(PRIVATE/FRIENDS/PUBLIC, 기본 PRIVATE).
  ///
  /// [emotion](프리셋 코드)과 [emotionLabel](자유 텍스트 ≤20자)은 **상호 배타**이며 둘 다 선택 사항이다
  /// (동시 지정 시 서버가 400 EMOTION_CONFLICT — 앱은 입력 위젯에서 사전 차단한다).
  /// POST /diaries
  Future<Diary> upsert({
    required DateTime date,
    required String content,
    required String contentText,
    bool confirm = false,
    String visibility = 'PRIVATE',
    String? emotion,
    String? emotionLabel,
  });

  /// 공개범위만 변경(본문 불변과 분리). 확정 기록도 허용된다.
  /// PATCH /diaries/{id}/visibility
  Future<Diary> changeVisibility(int id, String visibility);

  /// 소프트 삭제. 삭제 후 같은 날짜 재작성이 허용된다.
  /// DELETE /diaries/{id}
  Future<void> delete(int id);

  /// 본문에 삽입할 이미지 1장을 업로드하고 **서버 상대 경로 URL**을 돌려준다.
  ///
  /// 에디터가 작성 중 호출하며(기록 저장 전), 반환된 경로를 Quill Delta의 image
  /// 임베드로 본문에 삽입한다. 저장 시 서버가 Delta를 파싱해 실제 사용 이미지를 확정한다.
  /// POST /diaries/images (part명 "file")
  Future<String> uploadImage(Uint8List bytes, String filename);

  /// 내가 최근 사용한 커스텀 감정 라벨(중복 제거·최신순). 작성기 추천 칩에 쓴다.
  /// GET /diaries/me/emotions/recent
  Future<List<String>> getRecentEmotionLabels();
}
