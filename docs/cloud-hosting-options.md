# 클라우드 호스팅 옵션 비교·추천 (백엔드 + DB 공개 배포)

> **문서 성격**: 조사·의사결정 참고 자료. **현재는 문서화 단계이며 실제 배포는 미실시.**
> 가격·무료 티어 수치는 **2026-07 웹 조사 기준**이며 정책 변동이 잦으니 실행 전 각 출처를 재확인할 것.

## 1. 배경 — 왜 이 문서가 필요한가

앱(`recorme`)을 **웹(Netlify 등 정적 호스팅)** 이나 외부에서 접근 가능한 형태로 배포하려면, 프론트만으로는 부족하고 **백엔드와 DB가 공개 인터넷에서 HTTPS로 닿아야** 한다. 현재 백엔드는 **홈서버 + Tailscale 내부 전용**(`docs/deployment.md`)이라 Tailscale이 깔린 기기(폰)에서만 접근된다.

- **Netlify는 프론트(정적 사이트)만** 호스팅한다. Spring Boot 같은 상시 JVM 서버나 관리형 PostgreSQL은 **Netlify로 배포할 수 없다.** (Netlify 배포 모델 = base directory + build command + publish directory)
- 따라서 백엔드·DB는 **별도 클라우드**가 필요하다. 이 문서는 그 후보들을 비교한다.

## 2. 이 프로젝트에서 "클라우드에 새로 올릴 대상"

| 구성요소 | 현재 위치 | 클라우드 이전 필요? |
|---|---|---|
| 백엔드 (Spring Boot, Docker 이미지 존재) | 홈서버(Tailscale) | **O — 공개 HTTPS 필요** |
| PostgreSQL 18 (Flyway V1~V10) | 홈서버(Docker 볼륨) | **O — 공개 or 관리형** |
| Supabase Auth | 이미 클라우드 | X (그대로) |
| Gemini(LLM) API | 이미 클라우드 | X (그대로) |
| FCM(푸시) | 이미 클라우드 | X (그대로) |
| 프론트 Flutter Web | (미배포) | 정적 호스팅(Netlify 등)으로 별도 |

즉 **새로 올릴 것은 백엔드 + PostgreSQL 뿐이다.**

## 3. ⚠️ Spring Boot(JVM) 특성상 주의사항

- **메모리**: JVM 부팅만으로 300~512MB를 쓴다. 무료 티어의 **256MB(예: Koyeb)는 부족**, **512MB가 실질 하한선**이다.
- **콜드 스타트**: "미사용 시 슬립 → 재기동"(scale-to-zero) 방식은 첫 요청에 **30~50초**가 걸린다. 상시 서비스보다 **데모/체험용**에 적합.
- **Docker 자산 재사용**: 이미 `backend/Dockerfile`, `deploy/docker-compose.yml`이 있어 Docker/compose를 그대로 받는 플랫폼과 궁합이 좋다.

## 4. 플랫폼 비교 (2026-07 기준)

| 플랫폼 | 무료 티어 | 최소 유료 | 상시구동 | Docker | Postgres | 신뢰성 / 비고 |
|---|---|---|---|---|---|---|
| **Railway** | $5 최초 + 월 $1 크레딧(사실상 체험) | **$5/월 Hobby** | O | O(compose 네이티브) | O(원클릭) | 개발자 경험 최고, 소액 상시. **가장 현실적** |
| **Render** | 백엔드 무료(15분 후 슬립), DB 무료 1GB | $7/월~ | 슬립(콜드 30~50초) | O | O(**무료 DB는 30일 후 만료** ⚠️) | 신용카드 불필요, 데모용 |
| **Google Cloud Run** | 180K vCPU-초/월, scale-to-zero | 종량제 | 슬립 | O | ✗(별도 DB 필요) | 무료 넉넉·신뢰↑, 콘솔 복잡·카드 필수 |
| **AWS** | 신규계정(’25.7.15~) 12개월 무료 **폐지** → $200 크레딧 | Lightsail 고정 $3.5~5/월 | O | O | RDS 유료 | 신뢰성 최고·표준, 무료 아님·복잡 |
| **Oracle Cloud** | ARM Ampere 상시 무료(’26.6 **2 OCPU/12GB로 축소**) | 영구 무료 | O | O(직접 설치) | 직접 구성 | 유일한 "상시 완전 무료"지만 프로비저닝 난이도·유휴 회수·계정 정지 리스크 → **비추천** |
| **Fly.io** | 무료 티어 **폐지(2024)** | $2~3/월~ | O | O | O | Docker 친화적이나 무료 아님 |
| **Neon** (DB 전용) | serverless PostgreSQL 무료 0.5~3GB, **만료 없음** | 종량제 | — | — | O | Render 무료 DB의 30일 만료를 피하는 최선. 믿을 만함 |

## 5. 상황별 추천

- **① 완전 무료 우선(데모·체험)** → **Render(백엔드) + Neon(DB)**
  신용카드 불필요, 콜드 스타트·슬립만 감수. Render 무료 DB의 30일 만료 리스크를 **Neon(만료 없음)** 으로 회피.
- **② 소액으로 안정·편의(현실적 추천)** → **Railway Hobby $5/월**
  Docker/compose 네이티브 + Postgres 원클릭 + 상시 구동. 이 프로젝트의 `deploy/docker-compose.yml`과 궁합이 가장 좋고 믿을 만하다.
- **③ 대기업 신뢰성 필수** → **AWS Lightsail(고정 $5~)** 또는 **Google Cloud Run + Neon**
  표준적·안정적이나 무료가 아니거나(AWS) 콘솔이 복잡하다(GCP).
- **비추천: Oracle Cloud** — 유일하게 상시 완전 무료지만, 인스턴스 확보 난이도·유휴 회수·계정 정지 사례가 많아 *"믿을 만한"* 요구와 맞지 않는다.

## 6. 어느 플랫폼을 고르든 공통 선결 조건

플랫폼 선택과 무관하게, 외부(브라우저/공개망)에서 앱이 실제로 동작하려면 다음이 필요하다:

1. **백엔드 공개 HTTPS 노출** — Netlify(HTTPS)/브라우저에서 `http://` 호출은 혼합 콘텐츠로 차단된다.
2. **CORS 허용 origin 추가** — `backend/.../global/security/SecurityConfig.java`의 `corsConfigurationSource()`가 현재 `http://localhost:*`, `http://127.0.0.1:*`만 허용(`SecurityConfig.java:66~75`). 배포 도메인(예: `https://<site>.netlify.app`)을 추가해야 한다. `allowCredentials(true)`라 **와일드카드 불가 → 명시 도메인** 필요.
3. **앱 API base URL 주입** — `app/lib/core/config/api_config.dart:10`의 기본값이 에뮬레이터 주소(`http://10.0.2.2:8080`). 빌드 시 `--dart-define=API_BASE_URL=https://<공개-백엔드>` 주입 필요.
4. **DB 마이그레이션 이관** — Flyway `V1~V10`은 자동 적용되나, 관리형 Postgres(Neon 등)로 옮길 경우 접속 정보(`DB_URL`/`DB_USER`/`DB_PASSWORD`)만 교체하면 된다.
5. **(프론트도 배포 시)** SPA 리다이렉트(`_redirects` `/* /index.html 200`) + Supabase/Google/Kakao 콘솔에 배포 origin을 OAuth redirect로 등록.

## 7. (참고) Netlify 프론트 정적 배포 가능성 요약

- **결론: 조건부 가능.** `app/web/`가 이미 존재하고 `dart:io` 미사용, 네이티브 플러그인은 `kIsWeb` 가드/웹 지원 패키지로 처리됨. `flutter build web` 산출물(`build/web`)을 base=`app`, publish=`build/web`로 배포.
- 단 **Netlify 빌드 이미지에 Flutter SDK가 없음** → CI(Codemagic/로컬)에서 빌드 후 산출물만 올리거나 빌드 커맨드에 Flutter 설치 스텝을 추가해야 한다.
- **웹에서 의도적으로 제외된 기능**(동작 지장 없음): FCM 푸시, 로컬 알림, 감정 영상 셰이더 합성(웹은 PNG 폴백). 관련 코드가 이미 웹 no-op/폴백 처리됨.

## 참고 출처 (2026-07 조사)

- [Free cloud deploy platforms 2026 — SnapDeploy](https://snapdeploy.dev/blog/free-cloud-deployment-platforms-2026-comparison)
- [Platforms with a real free tier for developers in 2026 — Render](https://render.com/articles/platforms-with-a-real-free-tier-for-developers-in-2026)
- [AWS Free Tier 2026 변경 — InfraTally](https://infratally.com/articles/aws-free-tier-2026.html)
- [Oracle 무료 티어 2 OCPU/12GB 축소 — TerminalBytes](https://terminalbytes.com/oracle-cloud-free-tier-changes-2026/)
- [Top PostgreSQL free tiers 2026 — Koyeb](https://www.koyeb.com/blog/top-postgresql-database-free-tiers-in-2026)
- [Netlify 빌드 설정 개요](https://docs.netlify.com/build/configure-builds/overview/)
