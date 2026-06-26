# 로컬 E2E 테스트 가이드 — 일기 CRUD · 사진 첨부 · 글자수 제한

> 목적: **Flutter 웹 + 로컬 백엔드 + 로컬 PostgreSQL 18(recorme)**로
> 일기 작성/조회/수정/삭제 + **사진 첨부(최대 5장)** + **글자수 500자 하드 제한**을 직접 확인한다.
> (인증·프로필 흐름은 `_LOCAL_E2E_TEST.md` 참고. 본 문서는 **일기 기능** 전용.)

---

## 0. 사전 검증 완료 (2026-06-26, 이미 확인됨)

`./gradlew bootRun` 1회 실행으로 다음을 실측했다:
- Flyway **V2(diaries)·V3(diary_images) 적용 성공** → `Started RecordApplication`
- 테이블 `diaries`·`diary_images` 생성, `chk_diaries_content_len`(1~500) 제약,
  인덱스 `uq_diary_user_day`/`idx_diaries_user_date`/`idx_diary_images_diary`/`uq_diaries_share_token` 확인
- 미인증 `GET/POST /diaries` → **401**(보안 정상)

즉 백엔드는 로컬 DB에서 바로 동작한다. 아래는 앱과 함께 UI로 끝까지 확인하는 절차다.

---

## 0-1. 웹 테스트 시 주의 (한글 IME)

리치 에디터(flutter_quill)는 **Flutter 웹에서 한글(CJK) IME 조합 입력이 제한**된다(영문은 정상).
이는 flutter_quill + Flutter 웹의 알려진 한계로, **한글 입력은 Android/iOS(모바일)에서 검증**한다.
→ 웹에서는 **영문 입력 · 서식(폰트/크기/굵게) · 인라인 이미지 · 미래 날짜 차단 · 목록 실시간 갱신** 위주로 확인.

## 0-2. 미래 날짜 차단 (2026-06-26 추가)

- 캘린더에서 **오늘 이후 날짜는 흐리게 표시되고 탭이 안 된다**(작성/조회 불가).
- 이번 달에서는 **다음 달(›) 버튼이 비활성**이고 좌측 스와이프로도 미래 달로 못 넘어간다(캘린더·목록 동일).
- 오늘/과거 날짜는 정상 진입.

---

## 1. 전제

- 로컬 **PostgreSQL 18** 실행 중, DB/롤 `recorme`(`application-local.yml` 값과 일치)
- Supabase 콘솔: **Authentication → Email provider Enable**, 빠른 테스트는 **Confirm email OFF** 권장
  (대시보드 `https://supabase.com/dashboard/project/wcrlawgpmwxyxohwlegc`)
- Supabase **URL Configuration → Site URL/Redirect URLs**에 `http://localhost:8000` 포함

---

## 2. 백엔드 실행 (터미널 1)

```bash
cd backend
SUPABASE_URL=https://wcrlawgpmwxyxohwlegc.supabase.co ./gradlew bootRun
```
- `http://localhost:8080` 기동, context-path `/api/v1`
- 첫 기동 시 Flyway가 V2/V3까지 자동 적용(이미 적용됐으면 "up to date")
- 사진은 **`backend/var/storage/diaries/yyyy/MM/{uuid}.ext`**에 저장되고, DB엔 경로(`/files/...`)만 저장됨
  (`record.storage.root` 기본 `./var/storage` — bootRun을 `backend/`에서 실행하므로 `backend/var/storage`)

## 3. 앱 웹 실행 (터미널 2)

```bash
cd app
flutter run -d chrome --web-port=8000 --dart-define=API_BASE_URL=http://localhost:8080
```
- `--dart-define=API_BASE_URL=http://localhost:8080` 필수(웹 기본값 `10.0.2.2`는 안드로이드 에뮬 전용)
- 로그인(이메일 가입/로그인) → 메인(캘린더) 진입. 이후 모든 일기 화면이 **실제 백엔드**를 호출한다.

> 사진 선택은 웹에서 파일 선택 다이얼로그로 동작한다(image_picker 웹). 실기기는 갤러리.

---

## 4. 테스트 시나리오

### 시나리오 1 — 일기 작성(글자수 제한) ⭐
1. 캘린더에서 **오늘 날짜 탭** → 에디터 진입(일기 없으면 신규).
2. 본문 입력 → 하단 **글자수 카운터** `n / 500` 갱신 확인.
3. **500자 초과 입력 시도** → 더 입력되지 않음(하드 제한). 카운터가 한도 근접 시 색 변화(노랑→빨강).
4. 저장 → "저장했어요" 스낵바 → 캘린더 복귀, 해당 날짜에 **dot 표시**.
5. DB 확인:
```bash
PGPASSWORD='<DB비번>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, user_id, written_date, left(content,20) AS content, analysis_status FROM diaries WHERE deleted_at IS NULL ORDER BY id DESC;"
```
→ 방금 작성한 행, `analysis_status='PENDING'`.

### 시나리오 2 — 사진 첨부(최대 5장) ⭐
1. 에디터에서 **"사진 추가"** → 이미지 1~3장 선택 → 썸네일 표시.
2. **5장까지** 추가하면 추가 버튼 **비활성**(6장째 막힘).
3. 저장 → 본문 upsert 후 사진 업로드.
4. DB·디스크 확인:
```bash
# DB: diary_images 행(경로만)
PGPASSWORD='<DB비번>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, diary_id, image_url, sort_order FROM diary_images ORDER BY diary_id, sort_order;"
# 디스크: 실제 파일
ls -R backend/var/storage/diaries 2>/dev/null
```
→ DB엔 `/files/diaries/...` 경로만, 디스크엔 실제 이미지 파일 존재.

### 시나리오 3 — 목록·상세 조회
1. 하단 **목록 탭** → 작성 일기 날짜 역순 노출, **대표 썸네일 + 사진 개수 배지**(사진 있는 일기).
2. 스크롤로 추가 페이지 로딩(커서 무한 스크롤).
3. 항목 탭 → **상세**: 본문 전체 + **첨부 사진 갤러리** 표시.

### 시나리오 4 — 같은 날짜 재작성(수정 = UPDATE) (엣지)
1. dot 있는 날짜 탭 → 상세 → **수정** → 내용 변경/사진 추가·삭제 → 저장.
2. DB 확인: 같은 `id` 행의 `content`·`updated_at` 갱신(새 행 INSERT 아님).
```bash
PGPASSWORD='<DB비번>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, written_date, updated_at, analysis_status FROM diaries ORDER BY id DESC LIMIT 5;"
```

### 시나리오 5 — 삭제 + 디스크 회수 ⭐ (엣지)
1. 사진 있는 일기 상세 → **삭제** → 확인 다이얼로그 → 메인 복귀.
2. DB·디스크 확인:
```bash
# 본문은 소프트삭제(deleted_at 채워짐), diary_images 행은 제거됨
PGPASSWORD='<DB비번>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, deleted_at FROM diaries ORDER BY id DESC LIMIT 5;" \
  -c "SELECT count(*) AS image_rows FROM diary_images;"
ls -R backend/var/storage/diaries   # 해당 일기 사진 파일이 사라졌는지
```
→ 일기 `deleted_at` 채워짐, **diary_images 행 0 + 디스크 파일 회수**(공간 절약).
3. 같은 날짜 다시 탭 → **신규 작성 가능**(부분 유니크가 삭제분 제외).

### 시나리오 6 — 사진 한도 초과(서버 거부) (선택)
- 이미 5장인 일기에 추가 업로드 시 서버가 **409 IMAGE_LIMIT_EXCEEDED** → 앱 에러 안내.
  (앱이 클라이언트에서 먼저 막지만, API 직접 호출 시 서버에서도 차단됨)

---

## 5. 빠른 DB 덤프 (일기+사진)
```bash
PGPASSWORD='<DB비번>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost -c "
SELECT d.id, d.written_date, d.analysis_status, d.deleted_at IS NOT NULL AS deleted,
       count(i.id) AS images
  FROM diaries d LEFT JOIN diary_images i ON i.diary_id = d.id
 GROUP BY d.id ORDER BY d.id DESC;"
```

---

## 6. 트러블슈팅

| 증상 | 원인 / 확인 |
|---|---|
| 캘린더/목록 진입 시 **401** | 로그인 안 됨 또는 토큰 만료. 재로그인. 백엔드 로그 `INVALID_TOKEN`이면 `supabase.url`·인터넷(JWKS) 확인 |
| 일기 저장은 되는데 **사진이 안 올라감** | multipart 한도/파일 형식. jpg/png/webp·장당 5MB 이하인지. 백엔드 로그 `INVALID_FILE`/`FILE_TOO_LARGE` |
| 사진이 화면에 **깨져 보임** | `API_BASE_URL` 불일치(이미지 URL은 `resolveImageUrl`이 apiBaseUrl로 조립). 웹은 `http://localhost:8080`인지 |
| 목록/상세 **이미지 안 보임** | 백엔드 정적 서빙 `/files/**`(permitAll) 동작·`backend/var/storage`에 파일 존재 확인 |
| 브라우저 **CORS 에러** | `SecurityConfig` CORS(localhost) 확인 |
| 500자 초과가 **저장됨** | 앱 maxLength는 입력 차단. API 직접 호출 시엔 DB CHECK(23514)가 막음 → 400/500. 정상 경로(앱)에선 발생 안 함 |

---

## 7. 참고
- 감정 분석·테마·음악은 **Phase 4** 범위라 현재 `analysis_status`는 항상 `PENDING`으로 남는다(정상).
- 백엔드 Testcontainers(DiaryServiceTest·DiaryIntegrationTest)는 **Docker 일괄 검증** 예정(별도).
- image_picker 실제 갤러리 선택은 자동화 테스트로 커버 불가 → 본 수동 시나리오로 확인.
