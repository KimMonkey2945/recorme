#!/usr/bin/env bash
# recorme 릴리즈 APK 빌드 (Linux/macOS/WSL)
#
# 사용법:
#   ./scripts/build_release.sh http://100.x.y.z:8080
#   ./scripts/build_release.sh https://your-host.your-tailnet.ts.net
#
# ⚠️ API_BASE_URL 을 주입하지 않으면 앱은 기본값(http://10.0.2.2:8080, 에뮬레이터 전용)으로
#    빌드되어 실기기에서 서버에 못 붙는다. 반드시 서버(Tailscale) 주소를 넣을 것.
#    URL 에 /api/v1 를 붙이지 말 것(앱이 자동으로 붙임). 포트까지만.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "사용법: $0 <API_BASE_URL>   예) $0 http://100.x.y.z:8080" >&2
  exit 1
fi

API_BASE_URL="$1"

# app/ 디렉터리(이 스크립트의 상위)로 이동
cd "$(dirname "$0")/.."

echo "API_BASE_URL = ${API_BASE_URL} 로 릴리즈 APK 빌드..."
flutter build apk --release --dart-define=API_BASE_URL="${API_BASE_URL}"

echo "완료: build/app/outputs/flutter-apk/app-release.apk"
echo "이 APK 를 폰에 전송해 설치(카톡/드라이브/USB). 업데이트는 같은 릴리즈 키로 덮어 설치."
