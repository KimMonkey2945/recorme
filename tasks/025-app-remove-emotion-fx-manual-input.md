# Task 025 — 앱 감정 연출 제거 + 작성기 감정 입력 위젯

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F018·F019 축소 (모바일 — 연출 제거 + 사용자 입력 UI)
- **상태**: ✅ 구현 완료 (2026-07-16)
- **선행**: Task 024(백엔드 flag + `emotion`/`emotionLabel` 필드 + `/diaries/me/emotions/recent`) — 완료

## 개요

연출의 주인공을 **감정 → 내 캐릭터 하나**로 일원화하기 위해, 감정 기반 시각 연출을 전부 제거한다.
감정 마스코트 mp4 6종·알파 셰이더·동적 배경 테마·상세 시네마틱 인트로·러닝 로딩 영상·PENDING 폴링을 걷어내고,
그 자리에 **작성기 감정 입력 위젯**(프리셋 6종 + 직접 입력)을 넣는다.

감정은 이제 **달력 점 색 + 감정 칩**에만 남는 순수 메타데이터다.

### 유지/제거 경계 (중요)
- **유지**: 로그인 마스코트 영상 3종과 `video_player` — **브랜딩 자산이므로 삭제 금지**.
- **제거**: 감정 연출 전용 자산만. 원본 영상/이미지는 `docs/`에 재인코딩 소스로 보존한다(파일 삭제 ≠ 자산 폐기).
- Task 024에서 확정 응답이 곧 `DONE`이므로 **분석중 폴링이 구조적으로 불필요**해진다.

## 관련 파일

### 삭제
- `app/lib/shared/widgets/emotion_video.dart`, `app/lib/shared/widgets/emotion_avatar.dart`
- `app/shaders/emotion_alpha.frag` + `pubspec.yaml`의 `shaders:` 섹션 + `flutter_shaders` 의존성
- `app/assets/emotions/**`, `app/assets/videos/running_sel.mp4` (원본은 `docs/`로 이관 보존)

### 수정
- `app/lib/features/diary/presentation/diary_detail_view.dart` — `_IntroPhase`·`_RunningIntroOverlay`·**PENDING 3초 폴링** 제거
- `app/lib/core/theme/diary_theme.dart` → `app/lib/core/theme/emotion_palette.dart`(**달력 점 색 + 감정 칩 색만**)
- `app/lib/core/theme/emotion_assets.dart` → `app/lib/core/theme/emotion_labels.dart`(**라벨만**, PNG/mp4 경로 제거)
- `app/lib/features/feed/presentation/*` — 감정 배경색 카드 → **중립 카드 + 감정 칩**
- `app/lib/features/diary/data/dto/diary_dto.dart` — `hasTheme` 제거, `emotionLabel` 추가

### 신규
- `app/lib/features/diary/presentation/widgets/emotion_input_section.dart` — 프리셋 칩 6종 + 직접 입력(≤20자) + 최근 감정 추천
- `app/lib/features/diary/presentation/diary_editor_view.dart` — 위 위젯 삽입 + 저장 payload에 `emotion`/`emotionLabel` 반영
- `app/test/features/diary/emotion_input_test.dart` — **신규**

## 수락 기준

- [ ] 감정 mp4·셰이더·`flutter_shaders`·감정 에셋 디렉터리 **전부 제거**, `pubspec.yaml` 정리
- [ ] 상세 화면에서 시네마틱 인트로·러닝 영상·**PENDING 폴링 코드 제거** → 확정 직후 즉시 DONE 렌더
- [ ] **로그인 마스코트 영상 3종·`video_player` 정상 동작 유지**(회귀 없음)
- [ ] 작성기 감정 입력: 프리셋 칩 6종 / "직접 입력"(≤20자 카운터) / 최근 사용 감정 추천 칩
- [ ] 프리셋과 직접 입력은 **상호 배타**(동시 선택 불가 → 백엔드 `EMOTION_CONFLICT` 사전 차단)
- [ ] **감정은 선택 사항** — 미입력 상태로 등록·확정 가능
- [ ] 달력 점 색·감정 칩만 감정 색을 사용, 그 외 배경/글자 동적 테마 없음
- [ ] `flutter analyze` **무경고**(삭제한 위젯·셰이더·에셋 참조 0건) + `flutter test` 전체 통과

## 구현 단계

1. [ ] 감정 연출 위젯·셰이더·에셋 제거 및 `pubspec.yaml`(`shaders:`·`flutter_shaders`·assets 경로) 정리
2. [ ] `diary_detail_view.dart`에서 인트로·러닝 오버레이·폴링 제거(빈 자리는 Task 032 `ReactionOverlay`가 채움)
3. [ ] `diary_theme.dart` → `emotion_palette.dart`, `emotion_assets.dart` → `emotion_labels.dart` 축소 전환
4. [ ] 피드·목록·상세를 중립 카드 + 감정 칩으로 재구성, `diary_dto.hasTheme` 제거·`emotionLabel` 추가
5. [ ] `emotion_input_section.dart` 구현(프리셋 칩·직접 입력·최근 감정 추천) 후 에디터에 삽입
6. [ ] `flutter analyze` 무경고 확인 → `flutter test` 실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (`flutter test`)

### 정상 경로
- [ ] 프리셋 칩 6종 렌더 · 선택 시 하이라이트 · 재탭 시 해제
- [ ] "직접 입력" 선택 → 텍스트 필드 노출 → 입력값이 저장 payload의 `emotionLabel`에 실림
- [ ] 최근 사용 감정 추천 칩 탭 → 직접 입력 필드에 값 채움
- [ ] **감정 미입력 상태로 등록·확정 성공**(감정은 선택 사항)
- [ ] 확정 직후 상세가 **폴링 없이 즉시 DONE 렌더**(로딩 스피너·러닝 영상 없음)

### 에러/예외
- [ ] 직접 입력 **21자 입력 차단**(maxLength) / **20자 경계값** 정상 통과
- [ ] 프리셋 선택 상태에서 직접 입력 선택 → 프리셋 자동 해제(**동시 지정 불가** — `EMOTION_CONFLICT` 사전 차단)
- [ ] 저장 실패(네트워크 오류) 시 에러 스낵바 노출 + 입력값 보존

### 엣지/회귀
- [ ] `flutter analyze` 클린 — 삭제된 `emotion_video`/`emotion_avatar`/`emotion_alpha.frag`/감정 에셋 **잔존 참조 0건**
- [ ] **로그인 화면 마스코트 영상 3종 정상 재생**(제거 대상이 아님을 회귀 테스트로 고정)
- [ ] 달력 점 색·피드 감정 칩이 `emotion_palette` 색을 사용 / 상세·목록에 동적 배경색 미적용
- [ ] 커스텀 라벨(`emotionLabel`)만 있는 기록도 칩이 정상 렌더(프리셋 색 없이 중립 색)
- [ ] 감정 없는 기록도 카드·상세가 깨지지 않음(칩 영역 생략)

## 변경 사항 요약 (2026-07-16 구현 완료)

- **삭제**: `shared/widgets/emotion_video.dart`·`emotion_avatar.dart`, `core/theme/diary_theme.dart`·`emotion_assets.dart`, `shaders/emotion_alpha.frag`(+ `shaders/` 디렉터리), `assets/emotions/**`, `assets/videos/running_sel.mp4`. `pubspec.yaml`에서 `flutter_shaders`·`shaders:`·`assets/emotions/*` 제거.
- **신규 테마**: `core/theme/emotion_palette.dart`(감정 코드→accent 색, 달력 점·감정 칩 전용) + `core/theme/emotion_labels.dart`(프리셋 6종 `kEmotionPresets`·`emotionLabelOf`·`emotionEmojiOf`).
- **신규 위젯**: `diary/presentation/widgets/emotion_input_section.dart` — 프리셋 6종 칩 + "직접 입력"(≤20자, `LengthLimitingTextInputFormatter`) + 최근 추천 칩. 상호 배타(프리셋↔직접입력), 재탭 해제, `(emotion, emotionLabel)` 콜백.
- **에디터 배선**: `diary_editor_view.dart`에 감정 섹션 삽입(+ `onEmotionChanged`/`initial*`/`recentEmotionLabels` 파라미터), `diary_editor_page.dart`가 감정 상태 보유·프리필·저장 payload 반영, `providers/diary_providers.dart`에 `recentEmotionLabelsProvider` 추가.
- **저장소**: `DiaryRepository.upsert`에 `emotion`/`emotionLabel` 파라미터 + `getRecentEmotionLabels()` 추가(Api/Fake/E2E/Stub 전부 구현). `diary_dto.dart`에 `emotionLabel` 추가·`hasTheme`→`hasEmotion`.
- **상세 재작성**: `diary_detail_view.dart`를 인트로/영상/러닝 오버레이 없는 읽기 전용 뷰 + 감정 칩으로 재작성. `diary_detail_page.dart`의 PENDING 3초 폴링·`DiaryTheme` 팔레트 제거.
- **피드 중립화**: `feed_diary_card.dart`·`feed_diary_detail_page.dart`를 감정 배경색→중립 카드 + 감정 칩으로 전환(`EmotionAvatar`·`DiaryTheme` 제거).
- **캘린더**: 점 색을 감정 있을 때 `EmotionPalette.accentOf`로 표시.
- **테스트**: `test/features/diary/emotion_input_test.dart` 신규(6종 렌더·선택/해제·직접입력·20자 제한·상호배타·최근추천). `diary_ui_test.dart`·`diary_editor_view_test.dart`·`integration_test/diary_journey_test.dart`를 새 시그니처/구조로 수정. **`flutter analyze` 무경고 + `flutter test` 136개 통과**.
- **유지**: 로그인 마스코트 영상 3종·`video_player`(회귀 없음).

### 남은 연동
- **Task 032**: 상세에서 감정 인트로가 빠진 자리에 캐릭터 리액션 오버레이가 들어온다(확정 즉시 DONE이라 대기 0).
