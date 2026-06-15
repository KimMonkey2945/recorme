# record API 계약

> Base URL: `/api/v1`. 모든 응답은 표준 포맷을 따르며, 목록은 커서 페이징을 사용한다.

## 1. 표준 응답 포맷

```jsonc
// 성공
{ "success": true, "data": { /* ... */ }, "error": null }

// 실패
{ "success": false, "data": null, "error": { "code": "DIARY_NOT_FOUND", "message": "일기를 찾을 수 없습니다." } }
```

- HTTP 상태 코드는 의미에 맞게 사용(200/201/400/401/403/404/409/500). 본문 `error.code`로 세부 사유 구분.
- 인증 필요한 엔드포인트는 헤더 `Authorization: Bearer <accessToken>`.

## 2. 커서 페이징

- 요청: `?cursor=<lastId>&size=20` (첫 페이지는 `cursor` 생략).
- 응답 `data`: `{ "items": [...], "nextCursor": 1234, "hasNext": true }`.
- 정렬은 `id DESC`(최신순). OFFSET 미사용.

## 3. 엔드포인트

### 인증 (auth)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/auth/login` | 소셜 토큰 검증 후 JWT 발급(없으면 가입) | ✕ |
| POST | `/auth/refresh` | refresh 토큰 회전·재발급 | ✕ |
| POST | `/auth/logout` | refresh 토큰 폐기 | ○ |

```jsonc
// POST /auth/login  요청
{ "provider": "KAKAO", "token": "<social access/id token>" }
// 응답 data
{ "accessToken": "...", "refreshToken": "...",
  "user": { "uuid": "...", "nickname": "...", "profileImageUrl": "..." } }
```

### 일기 (diary)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/diaries` | 하루 기록 생성(하루 1개, 중복 날짜는 409) | ○ |
| PUT | `/diaries/{id}` | 기록 수정(내용 변경 시 감정 재분석) | ○ |
| GET | `/diaries/{id}` | 기록 상세(테마/음악/감정 포함) | ○ |
| GET | `/diaries/me` | 내 기록 목록(커서 페이징) | ○ |
| GET | `/diaries/shared/{shareToken}` | 공유 링크로 단건 조회 | 조건부 |
| DELETE | `/diaries/{id}` | 기록 소프트 삭제 | ○ |

```jsonc
// POST /diaries  요청
{ "content": "오늘은...", "writtenDate": "2026-06-15", "visibility": "FRIENDS" }
// 응답 data (분석 전)
{ "id": 10, "shareToken": "...", "content": "오늘은...", "writtenDate": "2026-06-15",
  "visibility": "FRIENDS", "analysisStatus": "PENDING", "theme": null, "track": null }

// GET /diaries/{id}  응답 data (분석 완료)
{ "id": 10, "content": "...", "writtenDate": "2026-06-15", "visibility": "FRIENDS",
  "analysisStatus": "DONE",
  "emotion": { "primaryEmotion": "CALM", "confidence": 0.82, "summary": "차분한 하루" },
  "theme": { "backgroundType": "GRADIENT", "backgroundValue": "{...}",
             "fontFamily": "nanum_handwriting", "textColor": "#222222FF" },
  "track": { "sourceType": "LOCAL_FILE", "sourceRef": "calm_01", "streamUrl": "...",
             "title": "...", "artist": "..." } }
```

> `analysisStatus`가 `PENDING`이면 클라이언트는 상세를 재조회(폴링)해 테마/음악을 갱신한다.

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
