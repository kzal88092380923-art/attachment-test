#!/usr/bin/env bash
# 애착유형테스트 배포 스크립트
# 화이트리스트 파일만 dist/로 복사해 배포 (og-image.html 같은 작업용 파일 제외)
# Draft 배포 → 경로 검증 통과 시에만 Production 승격 (netlify deploy --prod Forbidden 우회)
set -euo pipefail

SITE_ID="6b6c75c6-dc7a-4ba0-903a-8536911ca0de"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

WHITELIST=(
  index.html
  og-image.png
  sitemap.xml
  robots.txt
)

MUST_BE_404=(/og-image.html /deploy.sh /dist/)
MUST_BE_200=(/ /index.html /og-image.png /sitemap.xml /robots.txt)

cd "$SCRIPT_DIR"

if ! netlify status >/dev/null 2>&1; then
  echo "✗ Netlify 로그인이 필요합니다:  netlify login"
  exit 1
fi

echo "▶ dist/ 구성 (화이트리스트)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
for f in "${WHITELIST[@]}"; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo "✗ 화이트리스트 파일 없음: $f"
    exit 1
  fi
  cp "$SCRIPT_DIR/$f" "$DIST_DIR/"
  echo "  + $f"
done

echo "▶ Draft 배포 시작..."
DEPLOY_JSON=$(netlify deploy --dir="$DIST_DIR" --site="$SITE_ID" --json)
DEPLOY_ID=$(printf '%s' "$DEPLOY_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('deploy_id') or d.get('id') or '')")
DRAFT_URL=$(printf '%s' "$DEPLOY_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('deploy_url') or d.get('url') or '')")

if [ -z "$DEPLOY_ID" ] || [ -z "$DRAFT_URL" ]; then
  echo "✗ Deploy 정보 추출 실패. 원본:"
  printf '%s\n' "$DEPLOY_JSON"
  exit 1
fi
echo "✓ Draft 완료  ID: $DEPLOY_ID"
echo "  URL: $DRAFT_URL"

echo "▶ Draft 경로 검증"
FAILED=0
check() {
  local path="$1" expected="$2" code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$DRAFT_URL$path")
  if [ "$code" = "$expected" ]; then
    echo "  ✓ $path → $code"
  else
    echo "  ✗ $path → $code (기대값 $expected)"
    FAILED=1
  fi
}
for p in "${MUST_BE_404[@]}"; do check "$p" 404; done
for p in "${MUST_BE_200[@]}"; do check "$p" 200; done

if [ "$FAILED" -ne 0 ]; then
  echo "✗ 검증 실패 — Production 승격하지 않음 (draft만 남음)"
  exit 1
fi

echo "▶ Production 승격 중..."
netlify api restoreSiteDeploy \
  --data "{\"site_id\":\"$SITE_ID\",\"deploy_id\":\"$DEPLOY_ID\"}" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"✓ Production 승격 완료 (state: {d.get('state', '?')})\")
print(f\"🚀 Live: {d.get('ssl_url') or d.get('url', '?')}\")
"
