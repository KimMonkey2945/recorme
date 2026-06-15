# backend (Spring Boot)

`record`의 백엔드 애플리케이션입니다. 현재는 **도메인 기반 패키지 골격**만 잡혀 있으며,
실제 빌드 설정(`build.gradle`)·코드는 후속 단계에서 차근차근 추가합니다.

## 패키지 구조

```
com.recordapp
├─ global   (config / common / exception / security / util)
├─ domain   (auth / user / diary / emotion / theme / music / social)
└─ infra    (llm / music)
```

- MyBatis 매퍼 XML: `src/main/resources/mapper/`
- DB 마이그레이션(Flyway): `src/main/resources/db/migration/`

상세 설계는 [`../docs/backend.md`](../docs/backend.md), DB 스키마는 [`../docs/database.md`](../docs/database.md) 참고.

## 후속 스캐폴딩 (예정)

1. Spring Initializr로 `build.gradle` / `settings.gradle` / `RecordApplication.java` 생성
   - Gradle, Java 21, Spring Boot 3.x
   - 의존성: Spring Web, MyBatis, PostgreSQL Driver, Spring Security, Flyway, Validation
2. `application.yml` 작성 (DB·JWT·LLM 설정, 시크릿은 환경변수)
3. Flyway `V1__init.sql`에 [`../docs/database.md`](../docs/database.md)의 DDL 반영

> 각 패키지의 `.gitkeep`은 빈 디렉터리 추적용 placeholder이며, 실제 클래스 추가 시 삭제합니다.
