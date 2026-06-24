# Task 002 — 백엔드 공통 인프라 골격 (표준 응답·예외·JWT)

- **Phase**: 1 (애플리케이션 골격 구축)
- **구현 기능**: F001/F010 토대
- **상태**: 구현 완료 / 단위 테스트 통과(컨텍스트·Docker 테스트는 프로젝트 완성 후)

## 개요

`com.recordapp.global.*` 공통 인프라(표준 응답 래퍼, 전역 예외 처리, JWT 보안 골격, 커서 페이징 구조)와
`domain.auth.social`의 `SocialVerifier` 추상화·라우팅 골격을 구축한다. 실제 로그인/토큰 발급 로직은 Phase 3.

## 관련 파일

- `global/common/ApiResponse.java` — `{success, data, error}` 래퍼(ok/fail 빌더, 중첩 `ApiError`)
- `global/common/PageResponse.java` — `{items, nextCursor, hasNext}` 커서 페이지
- `global/common/CursorRequest.java` — `cursor`/`size`(기본 20·최대 50 보정)
- `global/exception/ErrorCode.java` — 에러 코드 enum + HTTP 상태 매핑
- `global/exception/BusinessException.java` — ErrorCode 기반 비즈니스 예외
- `global/exception/GlobalExceptionHandler.java` — `@RestControllerAdvice`(비즈니스/검증/500 마스킹)
- `global/security/JwtProperties.java` — `record.jwt.*` 설정 바인딩
- `global/security/JwtProvider.java` — access 토큰 발급/검증, principal 추출
- `global/security/JwtAuthenticationFilter.java` — Bearer 토큰 검증 → SecurityContext
- `global/security/JwtAuthenticationEntryPoint.java` — 401 표준 JSON 응답
- `global/security/SecurityUser.java` — 인증 principal(userId, uuid)
- `global/security/SecurityConfig.java` — STATELESS, `/auth/**`·`GET /diaries/shared/**` permitAll
- `global/util/HashUtil.java` — refresh 토큰용 SHA-256 hex
- `global/config/MyBatisConfig.java` — `@MapperScan(com.recordapp.domain.**.mapper)`
- `domain/auth/social/{Provider, SocialUserInfo, SocialVerifier, SocialVerifierRouter}.java` — provider별 검증 추상화·라우팅 골격
- `build.gradle` — jjwt 0.12.6 의존성 추가
- `application.yml` / `application-local.yml` / `src/test/resources/application-test.yml` — `record.jwt.*`(시크릿 env 주입, local/test dev 기본값)
- 테스트: `JwtProviderTest`, `HashUtilTest`(Docker 불필요 단위 테스트)

## 수락 기준

- [x] 표준 응답 래퍼 + 공통 응답 빌더
- [x] 전역 예외 핸들러 + 에러 코드 enum(DIARY_NOT_FOUND, UNAUTHORIZED 등) + HTTP 상태 매핑
- [x] JWT 발급/검증 유틸 골격 + refresh SHA-256 해시 유틸
- [x] 인증 필터 / SecurityConfig 골격(STATELESS, `/auth/**` permitAll)
- [x] 확장 포인트 인터페이스 격리: `SocialVerifier`(provider별 검증) + 라우팅
- [x] 커서 페이징 공통 응답 구조(items, nextCursor, hasNext)
- [x] 전체 컴파일 + 단위 테스트 통과
- [ ] (보류) `@SpringBootTest` 컨텍스트 로드(Docker 필요) — 프로젝트 완성 후 일괄 검증

## 구현 단계

1. [x] `build.gradle`에 jjwt 0.12.6 추가, `application.yml`에 `record.jwt.*` 추가(시크릿 env 주입)
2. [x] `global/common` 표준 응답·페이지·커서 요청
3. [x] `global/exception` 에러코드·예외·전역 핸들러
4. [x] `global/security` JWT 발급/검증/필터/엔트리포인트/SecurityConfig
5. [x] `global/util/HashUtil`, `global/config/MyBatisConfig`
6. [x] `domain/auth/social` 추상화·라우팅 골격
7. [x] 단위 테스트(JwtProvider/HashUtil) 작성 + `./gradlew test --tests "com.recordapp.global.*"` 통과

## 테스트 체크리스트

- [x] JwtProvider: access 토큰 발급→파싱 라운드트립(userId/uuid 복원)
- [x] JwtProvider: 변조 토큰 거부(JwtException)
- [x] JwtProvider: 만료 토큰 거부(JwtException)
- [x] HashUtil: SHA-256 표준 벡터("abc") + 64 hex + 결정성
- [ ] (보류, Docker) `@SpringBootTest` 컨텍스트 로드 시 SecurityConfig·예외 핸들러·필터 빈 정상 등록

## 변경 사항 요약

- 표준 응답/예외/JWT/커서 페이징 공통 인프라와 SocialVerifier 골격 구축 완료. jjwt 0.12.6 도입.
- JWT 시크릿은 `JWT_SECRET` 환경변수 주입(코드·git 평문 금지), local/test는 dev 전용 기본값 사용.
- `SocialVerifierRouter`는 현재 등록 구현체가 없어 모든 resolve가 `UNSUPPORTED_PROVIDER`(Phase 3에서 Kakao/Google 구현 추가).
