#!/usr/bin/env bash
# 로컬 백엔드(localhost:8080)에 붙는 Flutter 웹 실행.
# 웹 포트 8000 고정(Supabase Site URL/Redirect가 localhost:8000일 때 구글 OAuth 콜백과 일치).
# 웹 테스트 로그인은 이메일/비밀번호가 가장 단순(리다이렉트 불필요). 구글 OAuth는 콘솔 등록 필요.
# 한글 IME는 flutter_quill 웹 한계로 조합 입력이 제한됨(영문 정상) — 소셜(친구/피드/공감) 테스트엔 무관.
set -euo pipefail
cd "$(dirname "$0")/../app"
exec flutter run -d chrome --web-port=8000 \
  --dart-define=API_BASE_URL=http://localhost:8080
