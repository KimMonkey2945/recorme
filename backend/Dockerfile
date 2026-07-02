# syntax=docker/dockerfile:1
# =============================================================================
# recorme 백엔드 컨테이너 이미지 (멀티스테이지, self-contained)
#
# 빌드가 이미지 "안"에서 일어나므로 호스트/Jenkins의 JDK·JAVA_HOME 설정에 의존하지 않는다.
#   → 과거 "JAVA_HOME 누락으로 배포가 조용히 실패"한 유형의 사고를 구조적으로 차단한다.
#
# 빌드:   docker build -t recorme-backend:latest .
# (Jenkins 파이프라인이 backend/ 컨텍스트에서 이 파일로 이미지를 빌드한다.)
# =============================================================================

# ----- Build stage: bootJar 생성 -----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

# 1) Gradle 래퍼·빌드스크립트 먼저 복사. /root/.gradle 캐시 마운트로 래퍼 배포판·의존성을
#    빌드 간 재사용한다(BuildKit 필요 — 상단 syntax 지시자로 활성화). 두 RUN 이 같은 캐시를 공유.
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN --mount=type=cache,target=/root/.gradle chmod +x gradlew && ./gradlew --version --no-daemon

# 2) 소스 복사 후 실행 가능 jar 빌드.
#    통합테스트(Testcontainers)는 Docker 데몬이 필요해 이미지 빌드 단계에서 제외한다(-x test).
#    테스트는 서버에서 별도로 `./gradlew test`로 일괄 실행한다(ROADMAP 잔여 검증).
#    소스가 바뀌어도 anthropic-java·firebase-admin 등 큰 의존성은 캐시에서 재사용(5분 폴링 배포 부담↓).
COPY src ./src
RUN --mount=type=cache,target=/root/.gradle ./gradlew bootJar -x test --no-daemon

# ----- Runtime stage: JRE + 비루트 실행 -----
FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app

# 비루트 유저로 실행(권한 최소화)
RUN groupadd --system app && useradd --system --gid app --home /app app

# 빌드 산출물 복사 (record-0.0.1-SNAPSHOT.jar)
COPY --from=build /workspace/build/libs/*.jar app.jar

# 파일 스토리지 기본 경로. compose에서 이 경로를 호스트 볼륨에 바인드 마운트하고
# STORAGE_ROOT=/app/var/storage 로 주입한다(사진 영속화).
RUN mkdir -p /app/var/storage && chown -R app:app /app
USER app

EXPOSE 8080

# 컨테이너 헬스체크: context-path(/api/v1)를 포함한 경로로 TCP/HTTP 확인.
# actuator 미도입 상태이므로 루트 컨텍스트 응답(404여도 소켓 오픈 확인)으로 살아있음만 판단.
# ⚠️ bash 사용 필수: temurin(Ubuntu 기반)의 /bin/sh 는 dash 라 /dev/tcp·echo -e 를 지원하지 않아
#    sh 로는 상시 unhealthy 로 오판된다. (actuator 도입 시 /api/v1/actuator/health 로 교체 권장.)
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && echo -e 'GET /api/v1/ HTTP/1.0\\r\\n\\r\\n' >&3 && head -1 <&3 | grep -q HTTP"]

ENTRYPOINT ["java", "-jar", "app.jar"]
