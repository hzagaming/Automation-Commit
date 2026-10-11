#!/bin/bash

set -euo pipefail

# ============================================================
# 配置区：通常只需要确认这里
# ============================================================

GITHUB_USER="hzagaming"
GIT_NAME="hzagaming"
GIT_EMAIL="17358677225@163.com"

REPO_NAME="daily-progress"
REPO_DIR="$HOME/Documents/GitHub/$REPO_NAME"

# 中国 / 新加坡使用 +08:00；日本使用 +09:00
TIMEZONE="+08:00"
COMMIT_TIME="20:00:00"

# public 或 private
REPO_VISIBILITY="public"

# ============================================================
# 函数区
# ============================================================

fail() {
  echo
  echo "错误：$1" >&2
  echo
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

valid_macos_date() {
  local input_date="$1"
  local parsed

  [[ "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1

  parsed="$(date -j -f "%Y-%m-%d" "$input_date" "+%Y-%m-%d" 2>/dev/null || true)"
  [[ "$parsed" == "$input_date" ]]
}

read_diary() {
  local target_date="$1"
  local line
  local content=""

  echo >&2
  echo "--------------------------------------------------" >&2
  echo "请填写 $target_date 的日记。" >&2
  echo "可以输入多行；写完后单独输入 END 并回车。" >&2
  echo "--------------------------------------------------" >&2

  while IFS= read -r line; do
    [[ "$line" == "END" ]] && break
    content="${content}${line}"$'\n'
  done

  printf "%s" "$content"
}

first_nonempty_line() {
  printf "%s\n" "$1" |
    sed -n '/[^[:space:]]/{
      s/^[[:space:]]*//
      s/[[:space:]]*$//
      p
      q
    }'
}

ensure_repository() {
  mkdir -p "$HOME/Documents/GitHub"

  if [[ ! -d "$REPO_DIR/.git" ]]; then
    if [[ -e "$REPO_DIR" ]] && [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null || true)" ]]; then
      fail "$REPO_DIR 已存在且不是 Git 仓库，请先检查该目录"
    fi

    if gh repo view "$GITHUB_USER/$REPO_NAME" >/dev/null 2>&1; then
      echo "发现远程仓库，正在克隆……"
      rm -rf "$REPO_DIR"
      gh repo clone "$GITHUB_USER/$REPO_NAME" "$REPO_DIR"
    else
      echo "未发现仓库，正在从零创建……"
      mkdir -p "$REPO_DIR"
      cd "$REPO_DIR"

      git init -b main
      git config user.name "$GIT_NAME"
      git config user.email "$GIT_EMAIL"

      mkdir -p logs

      cat > README.md <<'EOF'
# Daily Progress

用于记录每天真实完成的编程、数学学习和项目开发内容。

## 使用规则

- 每个日期使用独立日志文件
- 日记内容应对应当天真实完成的事项
- 不提交密码、Token、身份证件或其他隐私
- 脚本会根据日志日期设置 Git 提交日期
EOF

      git add README.md
      git commit -m "chore: initialize daily progress repository"

      if [[ "$REPO_VISIBILITY" == "private" ]]; then
        gh repo create "$GITHUB_USER/$REPO_NAME" \
          --private \
          --source=. \
          --remote=origin \
          --push
      else
        gh repo create "$GITHUB_USER/$REPO_NAME" \
          --public \
          --source=. \
          --remote=origin \
          --push
      fi
    fi
  fi

  cd "$REPO_DIR"

  git config user.name "$GIT_NAME"
  git config user.email "$GIT_EMAIL"

  local branch
  branch="$(git branch --show-current)"

  if [[ -z "$branch" ]]; then
    fail "当前仓库处于 detached HEAD 状态"
  fi

  if [[ "$branch" != "main" ]]; then
    fail "当前分支是 $branch，不是 main。请先运行：git switch main"
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    if gh repo view "$GITHUB_USER/$REPO_NAME" >/dev/null 2>&1; then
      git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    else
      if [[ "$REPO_VISIBILITY" == "private" ]]; then
        gh repo create "$GITHUB_USER/$REPO_NAME" \
          --private \
          --source=. \
          --remote=origin
      else
        gh repo create "$GITHUB_USER/$REPO_NAME" \
          --public \
          --source=. \
          --remote=origin
      fi
    fi
  fi

  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    echo "正在同步远程 main 分支……"
    git pull --rebase origin main
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo
    git status --short
    fail "仓库中存在未提交修改。请先处理后再运行脚本"
  fi
}

# ============================================================
# 主程序
# ============================================================

echo "=============================================="
echo " Daily Progress 交互式记录与提交脚本"
echo "=============================================="

need_command git
need_command gh
need_command date
need_command sort
need_command sed
need_command tr

gh auth status >/dev/null 2>&1 ||
  fail "GitHub CLI 尚未登录，请先运行：gh auth login"

ensure_repository

echo
echo "请输入需要添加的日期。"
echo "支持用空格或逗号分隔，例如："
echo
echo "2026-08-01 2026-08-02 2026-08-03"
echo "或"
echo "2026-08-01,2026-08-02,2026-08-03"
echo

read -r -p "日期： " DATE_INPUT

[[ -n "${DATE_INPUT//[[:space:],]/}" ]] ||
  fail "没有输入任何日期"

NORMALIZED_INPUT="${DATE_INPUT//,/ }"

# macOS 自带 Bash 3.2，因此不用关联数组。
read -r -a RAW_DATES <<< "$NORMALIZED_INPUT"

[[ "${#RAW_DATES[@]}" -gt 0 ]] ||
  fail "没有识别到有效日期"

TODAY="$(date +%F)"

for d in "${RAW_DATES[@]}"; do
  valid_macos_date "$d" ||
    fail "日期格式或日期本身无效：$d；请使用 YYYY-MM-DD"

  if [[ "$d" > "$TODAY" ]]; then
    fail "不能提交未来日期：$d；今天是 $TODAY"
  fi
done

# 去重并按日期升序处理。
IFS=$'\n' DATES=($(printf "%s\n" "${RAW_DATES[@]}" | sort -u))
unset IFS

echo
echo "将处理以下日期："
printf "  - %s\n" "${DATES[@]}"

CREATED_COUNT=0
SKIPPED_COUNT=0

for d in "${DATES[@]}"; do
  YEAR="${d%%-*}"
  LOG_DIR="logs/$YEAR"
  LOG_FILE="$LOG_DIR/$d.md"

  if [[ -e "$LOG_FILE" ]]; then
    echo
    echo "注意：$LOG_FILE 已存在。"
    read -r -p "覆盖并创建新的提交吗？[y/N] " OVERWRITE

    case "$OVERWRITE" in
      y|Y|yes|YES)
        ;;
      *)
        echo "已跳过 $d。"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
        ;;
    esac
  fi

  DIARY=""

  while [[ -z "$(printf "%s" "$DIARY" | tr -d '[:space:]')" ]]; do
    DIARY="$(read_diary "$d")"

    if [[ -z "$(printf "%s" "$DIARY" | tr -d '[:space:]')" ]]; then
      echo "日记不能为空，请重新输入。" >&2
    fi
  done

  mkdir -p "$LOG_DIR"

  cat > "$LOG_FILE" <<EOF
# $d

## 当天记录

$DIARY
EOF

  git add "$LOG_FILE"

  if git diff --cached --quiet; then
    echo "内容没有变化，已跳过 $d。"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  SUMMARY="$(first_nonempty_line "$DIARY")"

  # 防止提交标题过长。
  if [[ "${#SUMMARY}" -gt 60 ]]; then
    SUMMARY="${SUMMARY:0:60}…"
  fi

  TIMESTAMP="${d}T${COMMIT_TIME}${TIMEZONE}"

  GIT_AUTHOR_DATE="$TIMESTAMP" \
  GIT_COMMITTER_DATE="$TIMESTAMP" \
  git commit -m "docs($d): $SUMMARY"

  CREATED_COUNT=$((CREATED_COUNT + 1))
done

if [[ "$CREATED_COUNT" -gt 0 ]]; then
  echo
  echo "正在推送到 GitHub……"
  git push -u origin main
else
  echo
  echo "没有创建新的提交，因此无需推送。"
fi

echo
echo "=============================================="
echo "处理完成"
echo "新建提交：$CREATED_COUNT"
echo "跳过日期：$SKIPPED_COUNT"
echo "仓库地址：https://github.com/$GITHUB_USER/$REPO_NAME"
echo "=============================================="
echo

git status
echo
git log -8 \
  --pretty=format:'%h | %ad | %s' \
  --date=format-local:'%Y-%m-%d %H:%M:%S %z'

echo
