#!/bin/bash

set -euo pipefail

# ============================================================
# Daily Progress TXT 追加与中断恢复脚本 V14.5
# macOS Bash 3.2 兼容
# ============================================================

GITHUB_USER="hzagaming"
GIT_NAME="hzagaming"
GIT_EMAIL="17358677225@163.com"

REPO_NAME="daily-progress"
REPO_DIR="$HOME/Documents/GitHub/$REPO_NAME"

TIMEZONE="+08:00"
COMMIT_TIME="20:00:00"
REPO_VISIBILITY="public"

fail() {
  echo
  echo "错误：$1" >&2
  echo
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

trim_text() {
  printf "%s" "$1" |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

normalize_input_path() {
  local value="$1"

  value="$(trim_text "$value")"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value//\\ / }"

  if [[ "$value" == "~/"* ]]; then
    value="$HOME/${value#~/}"
  fi

  printf "%s" "$value"
}

require_gh_for_creation() {
  need_command gh

  gh auth status >/dev/null 2>&1 ||
    fail "GitHub CLI 尚未登录，请先运行：gh auth login"
}

create_or_clone_repository() {
  mkdir -p "$HOME/Documents/GitHub"

  if [[ -d "$REPO_DIR/.git" ]]; then
    return 0
  fi

  require_gh_for_creation

  if [[ -e "$REPO_DIR" ]] &&
     [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null || true)" ]]; then
    fail "$REPO_DIR 已存在且不是 Git 仓库"
  fi

  if gh repo view "$GITHUB_USER/$REPO_NAME" >/dev/null 2>&1; then
    echo "发现 GitHub 仓库，正在克隆……"
    rm -rf "$REPO_DIR"
    gh repo clone "$GITHUB_USER/$REPO_NAME" "$REPO_DIR"
    return 0
  fi

  echo "未发现 daily-progress 仓库，正在创建……"

  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"

  git init -b main
  git config user.name "$GIT_NAME"
  git config user.email "$GIT_EMAIL"

  mkdir -p logs

  cat > README.md <<'EOF'
# Daily Progress

用于保存可追溯的每日开发记录。

## 导入规则

- 从 TXT 中识别日期和原始行
- 已有日志只追加，不覆盖
- 相同来源内容不会重复导入
- 每个日期最多创建一个汇总 commit
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
}

validate_repository() {
  cd "$REPO_DIR"

  git config user.name "$GIT_NAME"
  git config user.email "$GIT_EMAIL"

  local branch
  branch="$(git branch --show-current)"

  [[ -n "$branch" ]] || fail "当前仓库处于 detached HEAD 状态"
  [[ "$branch" == "main" ]] ||
    fail "当前分支是 $branch，不是 main。请先运行：git switch main"

  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin \
      "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
  fi
}

build_pending_manifest() {
  local manifest_file="$1"
  local status_file="$2"

  git status --porcelain=v1 > "$status_file"

  python3 - "$status_file" "$manifest_file" <<'PY'
from pathlib import Path
import re
import sys

status_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

pattern = re.compile(
    r"^logs/(\d{4})/(\d{4}-\d{2}-\d{2})\.md$"
)

items = []
unsupported = []

for raw in status_path.read_text(
    encoding="utf-8",
    errors="replace",
).splitlines():
    if len(raw) < 4:
        continue

    path = raw[3:]

    if " -> " in path:
        path = path.split(" -> ", 1)[1]

    match = pattern.fullmatch(path)

    if not match:
        unsupported.append(path)
        continue

    year, value = match.groups()

    if not value.startswith(year + "-"):
        unsupported.append(path)
        continue

    items.append((value, path))

if unsupported:
    print("检测到日志之外的改动：", file=sys.stderr)

    for path in unsupported:
        print(f"  {path}", file=sys.stderr)

    raise SystemExit(2)

items = sorted(set(items))

with manifest_path.open("w", encoding="utf-8") as handle:
    for _, path in items:
        # 每行只保存一个路径，不使用制表符分隔。
        handle.write(path + "\n")

print(len(items))
PY
}

sync_remote_before_recovery() {
  git fetch origin main

  local behind_count
  behind_count="$(git rev-list --count HEAD..origin/main)"

  if [[ "$behind_count" -eq 0 ]]; then
    return 0
  fi

  echo "远程 main 领先 $behind_count 个 commit，正在安全同步……"

  git stash push -u \
    -m "V14.4 automatic recovery stash" >/dev/null

  git pull --rebase origin main

  if ! git stash pop; then
    fail "恢复日志时发生冲突，请运行 git status 查看冲突"
  fi
}

recover_pending_logs() {
  local status_file
  local manifest_file
  local total_count
  local current_index
  local created_count
  local file_path
  local target_date
  local timestamp

  status_file="$(mktemp)"
  manifest_file="$(mktemp)"

  if ! total_count="$(
    build_pending_manifest "$manifest_file" "$status_file"
  )"; then
    rm -f "$status_file" "$manifest_file"
    fail "仓库包含日志之外的改动，V14.5 不会自动处理"
  fi

  if [[ "$total_count" -eq 0 ]]; then
    rm -f "$status_file" "$manifest_file"
    return 0
  fi

  echo
  echo "检测到 $total_count 个中断后留下的日志改动。"
  echo "将保留所有文件内容，按日期逐个 commit 并立即 push。"
  echo

  sync_remote_before_recovery

  # 同步后重新生成清单，防止 stash 恢复改变状态。
  if ! total_count="$(
    build_pending_manifest "$manifest_file" "$status_file"
  )"; then
    rm -f "$status_file" "$manifest_file"
    fail "同步后检测到日志之外的改动"
  fi

  # 只取消暂存，不删除或覆盖工作区中的任何文件。
  git reset --quiet

  current_index=0
  created_count=0

  exec 8< "$manifest_file"

  while IFS= read -r file_path <&8; do
    [[ -n "$file_path" ]] || continue

    current_index=$((current_index + 1))

    target_date="$(basename "$file_path" .md)"

    echo "--------------------------------------------------"
    echo "[恢复 ${current_index}/${total_count}] ${target_date}"
    echo "文件：${file_path}"
    echo "--------------------------------------------------"

    git add -A -- "$file_path"

    if git diff --cached --quiet -- "$file_path"; then
      echo "没有可提交变化，跳过。"
      echo
      continue
    fi

    local git_timezone
    git_timezone="${TIMEZONE/:/}"
    timestamp="${target_date} ${COMMIT_TIME} ${git_timezone}"

    env \
      GIT_AUTHOR_DATE="$timestamp" \
      GIT_COMMITTER_DATE="$timestamp" \
      git commit \
        -m "docs(${target_date}): recover interrupted log update" \
        -- "$file_path"

    created_count=$((created_count + 1))

    echo "正在立即 push ${target_date}……"

    if ! git push -u origin main; then
      exec 8<&-
      rm -f "$status_file" "$manifest_file"
      fail "${target_date} 已在本地 commit，但 push 失败。网络恢复后运行：git push origin main"
    fi

    echo "${target_date} 恢复完成。"
    echo
  done

  exec 8<&-

  rm -f "$status_file" "$manifest_file"

  echo "中断恢复完成：创建并推送 $created_count 个 commit。"
  echo
}

append_one_date() {
  local target_date="$1"
  local snippet_file="$2"
  local source_name="$3"
  local fingerprint="$4"

  local year
  local log_dir
  local log_file
  local marker
  local timestamp

  year="${target_date%%-*}"
  log_dir="logs/$year"
  log_file="$log_dir/$target_date.md"
  marker="<!-- import-sha256:${fingerprint} -->"

  mkdir -p "$log_dir"

  if [[ -f "$log_file" ]] &&
     grep -Fq "$marker" "$log_file"; then
    echo "相同来源内容已经导入，跳过 ${target_date}。"
    return 1
  fi

  if [[ ! -f "$log_file" ]]; then
    printf '# %s\n' "$target_date" > "$log_file"
  fi

  {
    printf '\n\n## TXT 追加记录\n\n'
    printf '%s\n\n' "$marker"
    printf -- '- 来源文件：`%s`\n' "$source_name"
    printf -- '- 对应日期：`%s`\n\n' "$target_date"
    printf '### 原始内容\n\n'
    printf '```text\n'
    cat "$snippet_file"
    printf '```\n'
  } >> "$log_file"

  git add "$log_file"

  if git diff --cached --quiet -- "$log_file"; then
    echo "没有产生文件变化，跳过 ${target_date}。"
    return 1
  fi

  local git_timezone
  git_timezone="${TIMEZONE/:/}"
  timestamp="${target_date} ${COMMIT_TIME} ${git_timezone}"

  env \
    GIT_AUTHOR_DATE="$timestamp" \
    GIT_COMMITTER_DATE="$timestamp" \
    git commit \
      -m "docs(${target_date}): append imported progress record" \
      -- "$log_file"

  echo "已创建 ${target_date} 的唯一汇总 commit。"
  return 0
}

import_txt_file() {
  local txt_file="$1"
  local work_dir
  local manifest
  local snippets_dir
  local source_name
  local total_count
  local created_count
  local pushed_count
  local skipped_count
  local current_index
  local line
  local target_date
  local snippet_file
  local fingerprint

  work_dir="$(mktemp -d)"
  manifest="$work_dir/manifest.txt"
  snippets_dir="$work_dir/snippets"

  mkdir -p "$snippets_dir"

  source_name="$(basename "$txt_file")"

  python3 - \
    "$txt_file" \
    "$manifest" \
    "$snippets_dir" <<'PY'
from __future__ import annotations

import hashlib
import re
import sys
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

source_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
snippets_dir = Path(sys.argv[3])

try:
    text = source_path.read_text(encoding="utf-8-sig")
except UnicodeDecodeError:
    text = source_path.read_text(encoding="gb18030")

pattern = re.compile(
    r"(?<!\d)(\d{4}-\d{2}-\d{2})(?!\d)"
)

today = date.today()
date_lines = defaultdict(list)
invalid_dates = set()
future_dates = set()

for raw_line in text.splitlines():
    values = pattern.findall(raw_line)

    for value in values:
        try:
            parsed = datetime.strptime(
                value,
                "%Y-%m-%d",
            ).date()
        except ValueError:
            invalid_dates.add(value)
            continue

        if parsed > today:
            future_dates.add(value)
            continue

        normalized_line = raw_line.rstrip() or value

        if normalized_line not in date_lines[value]:
            date_lines[value].append(normalized_line)

if not date_lines:
    raise SystemExit(
        "TXT 中没有识别到可导入的 YYYY-MM-DD 日期。"
    )

ordered_dates = sorted(date_lines)

with manifest_path.open("w", encoding="utf-8") as manifest:
    for value in ordered_dates:
        snippet = "\n".join(date_lines[value]).strip() or value

        fingerprint_source = (
            source_path.name + "\n" + value + "\n" + snippet
        )
        fingerprint = hashlib.sha256(
            fingerprint_source.encode("utf-8")
        ).hexdigest()

        snippet_path = snippets_dir / f"{value}.txt"
        snippet_path.write_text(
            snippet + "\n",
            encoding="utf-8",
        )

        # 使用竖线分隔，不依赖 Bash 的制表符解析。
        manifest.write(
            f"{value}|{snippet_path}|{fingerprint}\n"
        )

print(f"识别到 {len(ordered_dates)} 个不同日期。")
print(f"最早日期：{ordered_dates[0]}")
print(f"最晚日期：{ordered_dates[-1]}")

if invalid_dates:
    print(f"忽略无效日期：{len(invalid_dates)} 个")

if future_dates:
    print(f"忽略未来日期：{len(future_dates)} 个")
PY

  total_count="$(wc -l < "$manifest" | tr -d ' ')"
  created_count=0
  pushed_count=0
  skipped_count=0
  current_index=0

  echo
  echo "已有日志保留，不覆盖。"
  echo "每个日期最多创建一个汇总 commit，并立即 push。"
  echo

  exec 3< "$manifest"

  while IFS= read -r line <&3; do
    target_date="${line%%|*}"
    line="${line#*|}"
    snippet_file="${line%%|*}"
    fingerprint="${line#*|}"

    current_index=$((current_index + 1))

    echo "--------------------------------------------------"
    echo "[${current_index}/${total_count}] ${target_date}"
    echo "--------------------------------------------------"

    if append_one_date \
         "$target_date" \
         "$snippet_file" \
         "$source_name" \
         "$fingerprint"; then

      created_count=$((created_count + 1))
      echo "正在立即 push ${target_date}……"

      if git push -u origin main; then
        pushed_count=$((pushed_count + 1))
        echo "${target_date} 已 commit 并成功 push。"
      else
        exec 3<&-
        rm -rf "$work_dir"
        fail "${target_date} 已在本地 commit，但 push 失败。网络恢复后运行：git push origin main"
      fi
    else
      skipped_count=$((skipped_count + 1))
    fi

    echo
  done

  exec 3<&-
  rm -rf "$work_dir"

  echo
  echo "=============================================="
  echo "V14.5 TXT 导入完成"
  echo "TXT 文件：$txt_file"
  echo "识别日期：$total_count"
  echo "新建 commit：$created_count"
  echo "成功 push：$pushed_count"
  echo "重复或无变化：$skipped_count"
  echo "=============================================="
}

echo "=============================================="
echo " Daily Progress TXT 追加与中断恢复脚本 V14.5"
echo "=============================================="

need_command git
need_command python3
need_command sed
need_command grep
need_command basename
need_command mktemp
need_command wc
need_command tr

LOCK_DIR="$HOME/.daily-progress-v14.5.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "检测到另一个 V14.5 实例正在运行；如确认没有运行，请删除：$LOCK_DIR"
fi

cleanup_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup_lock EXIT

create_or_clone_repository
validate_repository

if [[ -n "$(git status --porcelain)" ]]; then
  recover_pending_logs
fi

if [[ "${1:-}" == "--recover-only" ]]; then
  echo
  echo "恢复模式处理完成。"
  git status
  exit 0
fi

if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
  echo "正在同步远程 main 分支……"
  git pull --rebase origin main
fi

TXT_FILE="${1:-}"

if [[ -z "$TXT_FILE" ]]; then
  echo
  echo "请把包含日期的 TXT 文件拖入 Terminal，然后按回车。"

  if ! IFS= read -r -p "TXT 文件： " TXT_FILE; then
    fail "输入被中断"
  fi
fi

TXT_FILE="$(normalize_input_path "$TXT_FILE")"

[[ -n "$TXT_FILE" ]] || fail "没有提供 TXT 文件"
[[ -f "$TXT_FILE" ]] || fail "找不到 TXT 文件：$TXT_FILE"

import_txt_file "$TXT_FILE"

echo
git status
echo
git log -10 \
  --pretty=format:'%h | %ad | %s' \
  --date=format-local:'%Y-%m-%d %H:%M:%S %z'

echo
