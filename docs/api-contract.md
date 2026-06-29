# record API 계약

> Base URL: `/api/v1`. 모든 응답은 표준 포맷을 따르며, 목록은 커서 페이징을 사용한다.

> ⚠️ **이 문서는 확정 명세가 아니라 작업 기준 스냅샷이다.** 엔드포인트·요청/응답 형태·정책은 개발 진행과 요구사항 변화에 따라 **얼마든지 변경될 수 있으며**, 변경 시 관련 문서(PRD·backend·database)와 함께 정합을 맞춘다.

## 1. 표준 응답 포맷

```jsonc
// 성공
{ "success": true, "data": { /* ... */ }, "error": null }

// 실패
{ "success": false, "data": null, "error": { "code": "DIARY_NOT_FOUND", "message": "기록을 찾을 수 없습니다." } }
```

- HTTP 상태 코드는 의미에 맞게 사용(200/201/400/401/403/404/409/500). 본문 `error.code`로 세부 사유 구분.
- 인증 필요한 엔드포인트는 헤더 `Authorization: Bearer <Supabase access token>`.

## 2. 커서 페이징

- 요청: `?cursor=<lastId>&size=20` (첫 페이지는 `cursor` 생략).
- 응답 `data`: `{ "items": [...], "nextCursor": 1234, "hasNext": true }`.
- 정렬은 `id DESC`(최신순). OFFSET 미사용.

## 3. 엔드포인트

### 인증 (auth)

로그인·세션은 **앱이 Supabase Auth로 직접 처리**한다. 별도 백엔드 로그인/리프레시/로그아웃 엔드포인트는 없다.

- 앱: Supabase SDK로 **소셜 로그인**(구글 `signInWithIdToken` / 카카오 `signInWithOAuth`) 또는 **이메일 가입/로그인**(`signUp`(닉네임은 `user_metadata`) / `signInWithPassword`) → Supabase 세션(access JWT + refresh, SDK가 저장·자동 갱신).
- 앱→백엔드: 보호 API 호출 시 `Authorization: Bearer <Supabase access token>`.
- 백엔드: Supabase JWT를 검증(**JWKS ES256 비대칭**)하고 `sub`(uuid)로 `users`를 JIT 프로비저닝(최초 요청 시 자동 가입). **이메일·소셜 모두 동일 형식의 토큰이라 provider 분기 없이 같은 경로로 처리**된다.
- 로그아웃: 앱에서 `supabase.auth.signOut()`(백엔드 호출 없음).
- 401/만료 시: Supabase SDK가 자동 갱신, 갱신 불가 시 재로그인.

### 사용자/프로필 (users)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/users/me` | 현재 사용자 프로필 조회(JIT 프로비저닝 보장) | ○ |
| PUT | `/users/me` | 내 프로필 수정(닉네임·자기소개) | ○ |
| POST | `/users/me/avatar` | 프로필 이미지 업로드(multipart) | ○ |

```jsonc
// GET /users/me  응답 data
{ "uuid": "...", "nickname": "...", "email": "...", "profileImageUrl": "...", "bio": "..." }
// profileImageUrl: 내부 업로드는 상대 경로(/files/avatars/...), 외부 소셜 제공분은 절대 URL.
//                  앱이 http로 시작하면 그대로, 아니면 apiBaseUrl과 결합해 표시한다.

// PUT /users/me  요청 (nickname 필수, bio 선택. email·profileImageUrl은 이 경로에서 수정 불가)
{ "nickname": "새 닉네임", "bio": "한 줄 소개" }
// 응답 data: 갱신된 user (GET /users/me 와 동일 형태)
// 에러: 검증 실패(닉네임 빈값/길이 50 초과, bio 300 초과) → 400 VALIDATION_ERROR / 미인증 → 401 UNAUTHORIZED

// POST /users/me/avatar  요청: multipart/form-data, part name="file" (이미지 1개)
// 응답 data: 갱신된 user (profileImageUrl이 새 경로로 갱신됨). 검증·저장·DB 갱신을 즉시 수행.
// 에러: 비이미지/손상 파일 → 400 INVALID_FILE / 용량 초과 → 413 FILE_TOO_LARGE / 미인증 → 401 UNAUTHORIZED
```

> **프로필 이미지 = 백엔드 파일 업로드.** 닉네임/자기소개 수정(`PUT`)과 이미지 업로드(`POST .../avatar`)를 **분리**해, 텍스트 수정이 이미지를 덮어쓰지 않는다. 파일 바이너리는 백엔드 로컬 디스크에 저장하고 DB에는 경로만 보관한다(BYTEA 미사용, Supabase Storage 미사용). 허용 형식 jpg/png/webp, 최대 5MB(매직바이트 검증).

> provider 범위는 **이메일 + 소셜(카카오·구글)**. 소셜은 Supabase Authorized Client IDs로 검증, 이메일은 Supabase Email provider(확인 메일 필수). **애플은 추후 Supabase Apple provider로 확장**한다.

### 정적 파일 (files)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/files/**` | 업로드된 이미지 서빙(UUID 파일명) | ✕(공개) |

> 프로필 이미지는 공유 화면에서 비로그인자도 보므로 공개 서빙한다. 파일명이 UUID라 URL 추측·열거가 불가하다. 컨텍스트 경로를 포함한 실제 URL은 `/api/v1/files/...`이며, DB에는 호스트 비종속 상대 경로(`/files/...`)만 저장한다.

### 기록 (diary)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/diaries` | 하루 기록 저장(**upsert**: 날짜 미존재 시 생성, 존재 시 갱신). `confirm=false`→DRAFT 저장, `confirm=true`→확정(PENDING·분석 1회). 확정 기록 재저장 시 409 | ○ |
| PUT | `/diaries/{id}` | id 기반 기록 수정(**DRAFT만 수정 가능**, 확정 기록은 409 `DIARY_ALREADY_CONFIRMED`) | ○ |
| GET | `/diaries/{id}` | 기록 상세(테마/음악/감정 포함) | ○ |
| GET | `/diaries/me/summary?yearMonth=YYYY-MM` | 월별 기록 존재 요약(캘린더 dot 렌더링용) | ○ |
| GET | `/diaries/by-date/{date}` | 특정 날짜(YYYY-MM-DD) 내 기록 단건 조회 | ○ |
| GET | `/diaries/me` | 내 기록 목록(커서 페이징) | ○ |
| GET | `/diaries/shared/{shareToken}` | 공유 링크로 단건 조회 | 조건부 |
| DELETE | `/diaries/{id}` | 기록 소프트 삭제(+첨부 사진 행·디스크 파일 즉시 회수) | ○ |
| POST | `/diaries/{id}/images` | 첨부 사진 업로드(multipart, part명 `files`, 1~N장, 기록당 최대 5장·장당 5MB) | ○ |
| DELETE | `/diaries/{id}/images/{imageId}` | 첨부 사진 1장 삭제(행·디스크 파일 회수) | ○ |

```jsonc
// POST /diaries  요청 (날짜 키 기반 upsert)
// confirm: 생략/false → '등록'(DRAFT 저장, 수정 가능·미분석) / true → '오늘을 기억하기'(확정·감정분석 1회)
{ "content": "오늘은...", "writtenDate": "2026-06-15", "visibility": "FRIENDS", "confirm": false }
// 응답 data (분석 전) — 신규 생성은 201 Created, 기존 갱신은 200 OK
// content는 1~500자(앱 maxLength·백엔드 @Size(500)·DB CHECK 동일 상수). 초과 시 400 VALIDATION_ERROR.
// 이미 확정된(DRAFT 아닌) 날짜에 재저장 시 409 DIARY_ALREADY_CONFIRMED (삭제 후 재작성만 허용).
// ⚠️ MVP: theme/track/emotion 필드는 Phase 4. 현재 DiaryResponse는 images 포함, theme/track 미포함.
// 등록(confirm=false) 응답: analysisStatus="DRAFT"
{ "id": 10, "shareToken": "...", "content": "오늘은...", "writtenDate": "2026-06-15",
  "visibility": "FRIENDS", "analysisStatus": "DRAFT", "images": [] }
// 확정(confirm=true) 응답: analysisStatus="PENDING" → 이후 분석 완료 시 DONE
{ "id": 10, "shareToken": "...", "content": "오늘은...", "writtenDate": "2026-06-15",
  "visibility": "FRIENDS", "analysisStatus": "PENDING", "images": [] }

// GET /diaries/{id}  응답 data (MVP) — analysisStatus: DRAFT/PENDING/DONE/FAILED
{ "id": 10, "shareToken": "...", "content": "...", "writtenDate": "2026-06-15", "visibility": "FRIENDS",
  "analysisStatus": "PENDING",
  "images": [ { "id": 1, "url": "/files/diaries/2026/06/{uuid}.jpg" },
              { "id": 2, "url": "/files/diaries/2026/06/{uuid}.jpg" } ] }
//    (Phase 4에서 emotion/theme/track 필드가 추가될 예정 — analysisStatus=DONE 시 채워짐)

// POST /diaries/{id}/images  요청: multipart/form-data, part명 "files"(여러 장 가능)
//    응답 data: 갱신된 전체 이미지 목록 [{ id, url }]. 기록당 5장 초과 시 409 IMAGE_LIMIT_EXCEEDED,
//    비이미지/손상 파일 413·400(INVALID_FILE), 장당 5MB 초과 413(FILE_TOO_LARGE).
// DELETE /diaries/{id}/images/{imageId}  응답: success=true (행·디스크 파일 회수)
```

```jsonc
// GET /diaries/me/summary?yearMonth=2026-06  응답 data
// 해당 월에 (소프트 삭제되지 않은) 기록이 존재하는 날짜 목록 → 캘린더 dot 표시에 사용
{ "yearMonth": "2026-06", "dates": ["2026-06-01", "2026-06-03", "2026-06-15"] }

// GET /diaries/by-date/2026-06-15  응답 data
// 해당 날짜 기록이 없으면 404 + error.code = "DIARY_NOT_FOUND"
{ "id": 10, "shareToken": "...", "content": "...", "writtenDate": "2026-06-15", "visibility": "FRIENDS",
  "analysisStatus": "DONE", "images": [ /* { id, url } ... */ ] }

// GET /diaries/me?cursor=&size=  응답 data (커서 페이징, id DESC, OFFSET 미사용)
// 목록 항목은 N+1 회피를 위해 이미지 전체 대신 대표 1장(thumbnailUrl)·총 개수(imageCount)만 포함.
{ "items": [ { "id": 12, "content": "...", "writtenDate": "2026-06-16", "analysisStatus": "DONE",
               "thumbnailUrl": "/files/diaries/2026/06/{uuid}.jpg", "imageCount": 2 } ],
  "nextCursor": 12, "hasNext": true }
```

> **캘린더 진입 흐름**: 메인(캘린더) 화면은 `GET /diaries/me/summary`로 점(dot)을 그린다. 사용자가 날짜를 탭하면 `GET /diaries/by-date/{date}`로 단건을 조회해, **있으면 상세 화면, 404면 신규 작성 화면**으로 분기한다. 두 엔드포인트 모두 `(user_id, written_date)` 인덱스로 처리되어 `/diaries/me` 전체 페이징보다 효율적이다.

> `analysisStatus`가 `PENDING`이면(확정 직후) 클라이언트는 상세를 재조회(폴링)해 분석 결과(테마/음악)를 갱신한다. 상세 화면은 "분석 중(약 1분)"을 표시하고 `DONE`이 되면 자동 갱신한다.

> **하루 1기록 + draft→확정 정책**: `POST /diaries`는 `(user_id, written_date)` 부분 유니크(`deleted_at IS NULL`)를 충돌 키로 한 upsert다. 같은 날짜로 다시 저장하면 INSERT 대신 기존 행을 UPDATE한다. 덕분에 클라이언트는 기록 `id`를 몰라도 항상 `POST /diaries`(날짜+내용)만 호출하면 되고(신규/수정 분기 불필요), 다중 기기·오프라인 동기화로 인한 **중복 날짜 경쟁 조건(409)도 발생하지 않는다**. `confirm=false`는 `DRAFT`(미분석·수정가능)로 저장하고, `confirm=true`는 `PENDING`으로 **확정해 감정 분석을 1회** 수행한다. **`DRAFT` 상태인 기록만 수정 가능**하며, 확정된 기록에 재저장하면 409 `DIARY_ALREADY_CONFIRMED`다(삭제 후 같은 날짜 재작성은 허용). `PUT /diaries/{id}`는 상세 화면에서 id를 이미 아는 경우의 명시적 수정 경로이며, 동일하게 DRAFT만 수정 가능하고 확정 기록은 409다.

### 피드 (feed)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/feed?cursor=&size=` | 본인 + 공개(PUBLIC) + 친구(FRIENDS) 기록 피드 | ○ |

### 친구 (friends)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/friends/requests` | 친구 요청 | ○ |
| POST | `/friends/requests/{id}/accept` | 요청 수락 | ○ |
| POST | `/friends/requests/{id}/reject` | 요청 거절 | ○ |
| GET | `/friends` | 친구 목록 | ○ |
| DELETE | `/friends/{userUuid}` | 친구 삭제/차단 | ○ |

### 공감 리액션 (reactions)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/diaries/{id}/reactions` | 공감 추가(1인 1회) | ○ |
| DELETE | `/diaries/{id}/reactions` | 공감 취소 | ○ |

> 댓글 API는 초기 범위에서 제외(공감만 제공).

## 4. 가시성(visibility) 규칙

| 값 | 조회 가능 대상 |
|---|---|
| `PRIVATE` | 본인만 |
| `FRIENDS` | 본인 + 수락된 친구 |
| `PUBLIC` | 모든 사용자 (피드 노출) |

공유 링크(`shareToken`)는 가시성과 별개로, 링크 소지자에게 단건 조회를 허용하는 별도 통로다(정책은 구현 시 확정).
