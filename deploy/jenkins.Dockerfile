# =============================================================================
# Jenkins 커스텀 이미지 — docker CLI + buildx + compose v2 플러그인 포함
#
# 스톡 jenkins/jenkins:lts-jdk21 에는 docker CLI 도, `docker compose`(v2 cli-plugin)도 없다.
# Jenkinsfile 이 `docker build` 와 `docker compose` 를 모두 쓰므로 둘 다 설치한다.
# 또한 backend/Dockerfile·app/Dockerfile 이 BuildKit 전용 문법(`RUN --mount`, `--secret`)을
# 쓰므로 docker-buildx-plugin 도 설치한다(없으면 legacy builder 로 폴백해 빌드가 실패한다).
# 호스트 도커 데몬은 docker.sock 마운트로 사용(compose 서비스 참고).
# =============================================================================
FROM jenkins/jenkins:lts-jdk21

USER root

# Docker 공식 apt 저장소 등록 후 CLI + compose 플러그인 설치(데몬은 미포함, 소켓으로 호스트 사용)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
