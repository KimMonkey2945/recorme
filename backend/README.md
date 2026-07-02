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

## 감정 분석 LLM 설정 (Gemini 기본)

감정 분석 provider는 `record.llm.*`(`application.yml`)로 선택하며, **기본값은 `gemini`**다. 키는 반드시 환경변수로만 주입한다(코드·git 평문 금지).

```bash
# Gemini(기본) — LLM_API_KEY만 있으면 됨. provider/model은 기본값으로 충분하나 배포 시 명시 주입 권장
export LLM_API_KEY=<Google AI Studio에서 발급한 키>
export LLM_PROVIDER=gemini            # 기본값이라 생략 가능
export LLM_MODEL=gemini-2.5-flash-lite  # 기본값. thinking 미사용→절단 없음, 무료 등급 가능
                                        # ⚠️ gemini-2.0-flash 계열은 무료 등급 막힘(429), gemini-2.5-flash는 절단 위험
./gradlew bootRun
```

- **무키로 기동하면** `LlmConfig`가 자동으로 `StubLlmClient`(고정 NEUTRAL)를 선택한다(로컬/CI 동작 보장, 실제 분석 안 됨).
- **로컬에서 과금 없이 실제 분석**하려면 로컬 Ollama로 전환: `LLM_PROVIDER=ollama`(키 불필요, `localhost:11434`에 Ollama 서버 기동 필요).
- **배포**: `application-cloud.yml`에는 키를 넣지 않고(시크릿 평문 금지) 컨테이너/시크릿 매니저에 `LLM_API_KEY`(필수), `LLM_PROVIDER=gemini`, `LLM_MODEL=gemini-2.5-flash-lite`를 주입한다.
- ⚠️ Gemini 사용 시 일기 본문·첨부 이미지가 외부(Google)로 전송된다(로컬 Ollama와 달리 외부 전송).

## 후속 스캐폴딩 (예정)

1. Spring Initializr로 `build.gradle` / `settings.gradle` / `RecordApplication.java` 생성
   - Gradle, Java 21, Spring Boot 3.x
   - 의존성: Spring Web, MyBatis, PostgreSQL Driver, Spring Security, Flyway, Validation
2. `application.yml` 작성 (DB·JWT·LLM 설정, 시크릿은 환경변수)
3. Flyway `V1__init.sql`에 [`../docs/database.md`](../docs/database.md)의 DDL 반영

> 각 패키지의 `.gitkeep`은 빈 디렉터리 추적용 placeholder이며, 실제 클래스 추가 시 삭제합니다.
