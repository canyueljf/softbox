#!/bin/sh
# 应用坞 · 发布脚本
#
# 用法：
#   GH_TOKEN=ghp_xxx sh publish.sh
#
# 需要 token 具备：repo（创建仓库）+ contents（写文件与上传 Release 附件）
# 建议用 Fine-grained token，只勾选目标仓库的 Contents: Read and write，
# 有效期设短（7 天），用完立刻去 GitHub 撤销。
#
# 脚本做的事：
#   1. 建仓库（已存在则跳过）
#   2. 推送 documentation（README / LICENSE / CHANGELOG / compose / 校验清单）
#   3. 建 v1.0.0 Release
#   4. 上传三个安装包作为 Release 附件（不走 git，避免 100MB 限制）
#
set -eu

OWNER="${OWNER:-}"
REPO="${REPO:-softbox}"
TAG="${TAG:-v1.0.0}"
PKG_DIR="${PKG_DIR:-/vol2/1000/其它/资料/fpk/个人/软件盒子}"
API="https://api.github.com"

: "${GH_TOKEN:?请先设置 GH_TOKEN}"
[ -n "$OWNER" ] || { echo "请设置 OWNER（你的 GitHub 用户名）"; exit 1; }

SLUG="$OWNER/$REPO"
H_AUTH="Authorization: Bearer $GH_TOKEN"
H_JSON="Accept: application/vnd.github+json"

api() {
  method="$1"; path="$2"; shift 2
  curl -sS -X "$method" -H "$H_AUTH" -H "$H_JSON" "$@" "$API$path"
}

say() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }

# ---------- 0. 身份 ----------
say "校验 token"
ME=$(api GET /user | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -n1)
[ -n "$ME" ] || { echo "token 无效或没有 user 读取权限"; exit 1; }
ok "已登录为 $ME"
[ -n "$OWNER" ] || OWNER="$ME"

# ---------- 1. 建仓库 ----------
say "创建仓库 $OWNER/$REPO（闭源：不放源码）"
CODE=$(api GET "/repos/$SLUG" -o /dev/null -w '%{http_code}')
if [ "$CODE" = "200" ]; then
  ok "仓库已存在，跳过创建"
else
  api POST /user/repos -d "{
    \"name\": \"$REPO\",
    \"description\": \"应用坞 · 在飞牛 NAS 里直接安装并运行 Linux / Windows / 安卓应用（闭源发布，仅提供安装包）\",
    \"homepage\": \"https://github.com/$SLUG\",
    \"private\": false,
    \"has_issues\": true,
    \"has_wiki\": false,
    \"auto_init\": true
  }" >/dev/null
  ok "仓库已创建"
fi

# ---------- 2. 推送文档 ----------
say "推送文档"
for f in README.md LICENSE CHANGELOG.md docker-compose.yml install.sh SHA256SUMS.txt .gitignore; do
  [ -f "$f" ] || continue
  CONTENT=$(base64 -w0 "$f" 2>/dev/null || base64 "$f" | tr -d '\n')
  # 取现有 sha（更新时需要）
  SHA=$(api GET "/repos/$SLUG/contents/$f" 2>/dev/null | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -n1)
  if [ -n "$SHA" ]; then
    api PUT "/repos/$SLUG/contents/$f" -d "{\"message\":\"docs: update $f\",\"content\":\"$CONTENT\",\"sha\":\"$SHA\",\"branch\":\"main\"}" >/dev/null
    ok "更新 $f"
  else
    api PUT "/repos/$SLUG/contents/$f" -d "{\"message\":\"docs: add $f\",\"content\":\"$CONTENT\",\"branch\":\"main\"}" >/dev/null
    ok "新增 $f"
  fi
  chmod +x install.sh 2>/dev/null || true
done

# ---------- 3. 建 Release ----------
say "创建 Release $TAG"
BODY=$(cat CHANGELOG.md 2>/dev/null | head -c 4000 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
REL=$(api POST "/repos/$SLUG/releases" -d "{
  \"tag_name\": \"$TAG\",
  \"name\": \"应用坞 1.0.0\",
  \"body\": $BODY,
  \"draft\": false,
  \"prerelease\": false
}")
UP_URL=$(echo "$REL" | sed -n 's/.*"upload_url": *"\([^"]*\)".*/\1/p' | head -n1 | sed 's/{?name,label}//')
[ -n "$UP_URL" ] || { echo "Release 创建失败：$REL"; exit 1; }
ok "Release 已建：$UP_URL"

# ---------- 4. 上传三个包 ----------
say "上传安装包（约 1.8 GB，这一步比较久）"
for f in "应用坞-1.0.0.fpk" "应用坞-Win运行环境.ypk" "应用坞-安卓运行环境.ypk"; do
  SRC="$PKG_DIR/$f"
  [ -f "$SRC" ] || { echo "  找不到 $SRC"; exit 1; }
  say "  $f ($(du -h "$SRC" | cut -f1))"
  curl -sS --progress-bar -X POST \
    -H "$H_AUTH" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$SRC" \
    "$UP_URL?name=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$f")" \
    -o /tmp/up.json
  if grep -q '"browser_download_url"' /tmp/up.json; then
    ok "已上传 $f"
  else
    echo "  上传失败：$(head -c 400 /tmp/up.json)"; exit 1
  fi
done

echo
say "完成"
echo "仓库：https://github.com/$SLUG"
echo "发布：https://github.com/$SLUG/releases/tag/$TAG"
echo
echo "记得用完去 GitHub 撤销这个 token：https://github.com/settings/tokens"
