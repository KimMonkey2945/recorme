# Task 001 — 백엔드 스캐폴딩 및 DB 스키마 구축

- **Phase**: 1 (애플리케이션 골격 구축)
- **구현 기능**: 인프라 기반 (전 기능 공통 토대)
- **상태**: 구현 완료 / Docker 기반 검증 보류(프로젝트 완성 후 진행)

## 개요

`backend/`에 Spring Boot 실행 골격과 초기 DB 스키마(Flyway `V1__init.sql`)를 구축한다.
실제 비즈니스 로직 없이 애플리케이션이 독립적으로 빌드되고, 초기 스키마가 정의된 상태가 목표.

### 인프라 결정 (사전 합의)
- **데이터는 별도 PostgreSQL(Supabase 미사용)**: Spring Boot + MyBatis + Flyway로 별도 PostgreSQL에 연결한다(로컬: Docker, 배포: 관리형/자체호스팅). Supabase는 **Auth 전용**(데이터 저장·PostgREST/RLS/Edge Functions 미사용). 스키마 진실원은 **Flyway 단일**.
  - ⚠️ **갱신(결정 변경)**: 초기에는 "(B) Supabase 관리형 PostgreSQL을 데이터 저장소로도 사용"이었으나, **인증만 Supabase / 데이터는 별도 PostgreSQL**로 최종 확정. `application-cloud.yml`을 별도 PG 설정으로 정리하고 `supabase/migrations/*`(profiles·RLS·트리거)는 폐기함.
- **연결 시점**: 로컬 먼저(개발/테스트는 로컬 Docker PG + Testcontainers), 배포 DB 연결은 `application-cloud.yml` + 환경변수로 전환.

## 관련 파일

- `backend/build.gradle`, `backend/settings.gradle` — Gradle, Java 21, Spring Boot 3.5.15, 의존성
- `backend/gradlew`, `gradlew.bat`, `gradle/wrapper/*` — Gradle wrapper(8.14.5)
- `backend/src/main/java/com/recordapp/RecordApplication.java` — 메인 클래스
- `backend/src/main/resources/application.yml` — 공통 설정(MyBatis/Flyway/context-path `/api/v1`)
- `backend/src/main/resources/application-local.yml` — 로컬 Docker PG 프로파일
- `backend/src/main/resources/application-cloud.yml` — 배포 DB(별도 PostgreSQL, 환경변수 주입) + Supabase Auth 검증 프로파일
- `backend/src/main/resources/db/migration/V1__init.sql` — 초기 스키마(users, social_accounts, refresh_tokens, diaries)
- `backend/docker-compose.yml` — 로컬 PostgreSQL 16
- `backend/src/test/java/com/recordapp/RecordApplicationTests.java` — 컨텍스트 기동 검증(Testcontainers)
- `backend/src/test/java/com/recordapp/FlywayMigrationTest.java` — 마이그레이션·제약 검증(Testcontainers)

## 수락 기준

- [x] Gradle 빌드 설정(Java 21 toolchain, Spring Boot 3.5.15) 작성
- [x] 패키지 베이스 `com.recordapp` 메인 클래스 배치
- [x] Flyway `V1__init.sql` 작성 — MVP 4테이블 + `uq_diary_user_day` 부분 유니크(`WHERE deleted_at IS NULL`)
- [x] `application.yml` 3종(공통/local/cloud) 환경변수 주입 구조
- [x] 로컬 PostgreSQL `docker-compose.yml`
- [x] Testcontainers 테스트 코드 작성(컨텍스트 기동 + 마이그레이션/제약 시나리오)
- [ ] **(보류) Docker 기반 테스트 실행 통과** — 프로젝트 완성 후 진행하기로 결정

## 구현 단계

1. [x] Spring Initializr로 스캐폴드 생성(Gradle, Java 21, Boot 3.5.15, web/validation/security/mybatis/postgresql/flyway)
   - 비고: 계획상 "Boot 3.3.x"였으나 Initializr가 ≥3.5.0만 제공 → **3.5.15**로 상향. JDK 21 자동 프로비저닝 위해 `settings.gradle`에 foojay-resolver 추가.
2. [x] `build.gradle`에 Testcontainers(postgresql, junit-jupiter), spring-boot-testcontainers 추가
3. [x] `V1__init.sql` 작성 (theme_id/track_id FK와 emotion/theme/track/social 테이블은 Phase 4 V2+로 연기)
4. [x] `application.yml`(공통/local/cloud) + `docker-compose.yml`
5. [x] Testcontainers 테스트 작성
6. [x] 컴파일 검증(`./gradlew compileTestJava`) — BUILD SUCCESSFUL (JDK21 toolchain 자동 프로비저닝, 의존성 해결, 전체 컴파일 통과)
7. [ ] (보류) `./gradlew test` — Docker 필요, 프로젝트 완성 후

## 테스트 체크리스트 (Testcontainers, PostgreSQL — 실행은 보류)

> 테스트 **코드는 작성 완료**. Docker 데몬이 필요한 실제 실행은 사용자 결정에 따라 프로젝트 완성 후 일괄 검증한다.

- [ ] (a) Flyway V1 마이그레이션 무오류 적용 + `uq_diary_user_day` 부분 유니크 인덱스 생성 확인
- [ ] (b) 같은 `(user_id, written_date)` 중복 INSERT → 유니크 위반(SQLState 23505)
- [ ] (c) 소프트 삭제(`deleted_at`) 후 같은 날짜 재INSERT 허용
- [ ] (d) `ON CONFLICT (user_id, written_date) WHERE deleted_at IS NULL DO UPDATE … RETURNING id` upsert가 같은 행을 갱신

## 변경 사항 요약

- (작성 예정) 검증 완료 후 기재
