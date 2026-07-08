# syntax=docker/dockerfile:1
# =============================================================================
# recorme 앱(Android APK) 빌드 이미지 — self-contained
#
# Flutter SDK + Android SDK 가 베이스 이미지에 내장돼 있어, Jenkins/호스트에 Flutter·Android
# SDK 를 설치할 필요가 없다(백엔드 Dockerfile 과 같은 철학: "SDK 누락으로 조용히 실패" 차단).
#
# iOS 는 macOS 가 필요해 여기서 못 만든다 → iOS 는 Codemagic(codemagic.yaml) 사용.
#
# 빌드는 Jenkinsfile.app 이 수행한다. 로컬에서 직접 만들려면(예):
#   DOCKER_BUILDKIT=1 docker build --target build \
#     --build-arg API_BASE_URL=http://100.x.y.z:8080 \
#     --secret id=keyprops,src=android/key.properties \
#     --secret id=keystore,src=android/app/recorme-release.jks \
#     -t recorme-app-builder ./app
# APK 추출(scratch 실행 불가라 cp 로): docker create → docker cp → docker rm (Jenkinsfile.app 참고).
#
# ⚠️ 베이스 이미지 버전은 개발 PC와 동일한 Flutter 버전으로 고정한다. `stable` 태그는 최신을 따라가서
#    Flutter 가 TextInputClient 등 API 를 바꾸면 flutter_quill 11.5.0 이 미구현 멤버로 컴파일이 깨진다
#    (예: onFocusReceived 미구현). 개발 PC 는 Flutter 3.38.9(Dart 3.10.8)에서 정상 빌드되므로 그 버전으로 고정.
#    로컬 Flutter 를 올릴 때 이 태그도 함께 맞춘다(`flutter --version`).
# =============================================================================

FROM ghcr.io/cirruslabs/flutter:3.38.9 AS build
WORKDIR /workspace

# 실기기가 붙을 서버 주소(포트까지, /api/v1 없이). 미주입 시 앱 기본값(에뮬레이터 전용)으로 빌드돼
# 실기기에서 서버에 못 붙는다. Jenkinsfile.app 이 파라미터로 받아 --build-arg 로 넘긴다.
ARG API_BASE_URL

# 1) 의존성 먼저 복사(레이어 캐시). pub 캐시 마운트로 빌드 간 재사용.
COPY pubspec.yaml pubspec.lock ./
RUN --mount=type=cache,target=/root/.pub-cache flutter pub get

# 2) 소스 복사 후 릴리즈 APK 빌드.
COPY . .
# 서명 자료를 BuildKit secret 으로 주입한다(이미지 레이어에 안 남음). required=false 라 미주입 시
# key.properties 부재 → android/app/build.gradle.kts 가 debug 서명으로 폴백(테스트용, 덮어설치 불가).
#   - key.properties → android/key.properties
#   - keystore(.jks) → android/app/recorme-release.jks (key.properties 의 storeFile 기본값과 일치, :app 기준)
# pub·gradle 캐시 마운트로 재빌드 가속(anthropic 무관, Android Gradle 의존성 재사용).
RUN --mount=type=secret,id=keyprops,target=/workspace/android/key.properties,required=false \
    --mount=type=secret,id=keystore,target=/workspace/android/app/recorme-release.jks,required=false \
    --mount=type=cache,target=/root/.pub-cache \
    --mount=type=cache,target=/root/.gradle \
    flutter build apk --release --dart-define=API_BASE_URL="${API_BASE_URL}"
# 산출물: /workspace/build/app/outputs/flutter-apk/app-release.apk (Jenkinsfile.app 이 cp 로 추출)
