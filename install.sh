#!/bin/sh
# 应用坞 一键部署脚本（在 alpine 容器内运行，宿主机直接跑也可以）
#
#   sh install.sh                # 下载 + 校验
#   sh install.sh --verify-only  # 只校验
#   sh install.sh --force        # 已存在也重下
#
set -eu

WORK_DIR="${WORK_DIR:-/downloads}"
BASE_URL="${BASE_URL:-https://github.com/canyueljf/softbox/releases/download/v1.0.0}"
PAN_URL="${PAN_URL:-https://pan.baidu.com/s/1DpciuaHkdKUlyTSWSxk_hA?pwd=78mv}"
PAN_CODE="${PAN_CODE:-78mv}"
SUMS="${SUMS:-/SHA256SUMS.txt}"
MODE="install"

for a in "$@"; do
  case "$a" in
    --verify-only) MODE="verify" ;;
    --force) SKIP_EXISTING=0 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  esac
done

FILES="应用坞-1.0.0.fpk 应用坞-Win运行环境.ypk 应用坞-安卓运行环境.ypk"

say() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$*"; }
bad() { printf '\033[31m  ✗ %s\033[0m\n' "$*"; }

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ---------- 校验函数 ----------
verify_one() {
  f="$1"
  want="$2"
  got=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || true)
  if [ "$got" = "$want" ]; then
    ok "$(printf '%-32s' "$f") SHA-256 一致"
    return 0
  fi
  bad "$(printf '%-32s' "$f") SHA-256 不一致"
  printf '     期望 %s\n     实际 %s\n' "$want" "${got:-<读取失败>}"
  return 1
}

# ---------- 读取期望值 ----------
[ -f "$SUMS" ] || { bad "找不到校验文件：$SUMS"; exit 1; }

FAIL=0
if [ "$MODE" = "verify" ]; then
  say "只校验模式 · 目录 $WORK_DIR"
  while read -r sum name; do
    [ -n "${name:-}" ] || continue
    if [ ! -f "$name" ]; then
      bad "$(printf '%-32s' "$name") 文件缺失"
      FAIL=1
      continue
    fi
    verify_one "$name" "$sum" || FAIL=1
  done < "$SUMS"
  if [ "$FAIL" = "0" ]; then
    say "全部通过。"
    exit 0
  fi
  say "存在缺失或损坏的文件。"
  exit 1
fi

# ---------- 下载 + 校验 ----------
say "下载源：$BASE_URL"
say "目标目录：$WORK_DIR"
echo

while read -r sum name; do
  [ -n "${name:-}" ] || continue

  if [ -f "$name" ] && [ "${SKIP_EXISTING:-1}" = "1" ]; then
    if verify_one "$name" "$sum"; then
      continue
    fi
    say "  重新下载 $name"
    rm -f "$name"
  fi

  say "下载 $name ..."
  if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$name.part" "$BASE_URL/$name" || { bad "下载失败：$name"; rm -f "$name.part"; FAIL=1; continue; }
  else
    curl -fL --progress-bar -o "$name.part" "$BASE_URL/$name" || { bad "下载失败：$name"; rm -f "$name.part"; FAIL=1; continue; }
  fi
  mv "$name.part" "$name"
  if verify_one "$name" "$sum"; then
    :
  else
    FAIL=1
  fi
done < "$SUMS"

echo
if [ "$FAIL" != "0" ]; then
  bad "有文件下载失败或校验不通过。"
  say "安装包在百度网盘：$PAN_URL  提取码 $PAN_CODE"
  say "下载后放进 $WORK_DIR，再执行 sh install.sh --verify-only 校验。"
  exit 1
fi

cat <<EOF

$(printf '\033[32m全部就绪。\033[0m')

文件已在：$WORK_DIR

接下来的安装步骤（在飞牛上完成）：
  1. 打开「应用中心 → 手动安装」，选择 应用坞-1.0.0.fpk
  2. 需要跑 Windows 程序：设置 → 兼容性 → Windows 运行环境 → 从本地添加 Wine 环境
  3. 需要跑安卓程序：设置 → 兼容性 → 安卓运行环境 → 从本地添加安卓环境
     （或在文件管理器里直接双击对应的 .ypk，会弹确认框走安装流程）

EOF
