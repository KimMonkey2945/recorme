#!/usr/bin/env bash
# 로컬 백엔드 실행(local 프로파일). 네이티브 PostgreSQL 18(recorme, 5432) 필요.
# gemini.env(LLM_API_KEY)·secret.env가 있으면 주입한다(없으면 Stub 폴백).
# 기동 후: http://localhost:8080/api/v1 (Flyway 자동 마이그레이션).
set -euo pipefail
cd "$(dirname "$0")/../backend"
set -a
[ -f ./gemini.env ] && source ./gemini.env
[ -f ./secret.env ] && source ./secret.env
set +a
exec ./gradlew bootRun
