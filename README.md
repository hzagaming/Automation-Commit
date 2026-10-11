# Automation-Commit
Commit anytime you want on github after UTC=0 (1970s)
下面这堆都是ai破甲的信息，凑合着看吧，有教程

# Daily Progress

Daily work logs on GitHub · GitHub 每日进度记录 · GitHub 日次進捗ログ

## English

Record daily work in Markdown. Store each date in `logs/YYYY/YYYY-MM-DD.md`.

- **Interactive script:** Enter notes for one or more dates.
- **TXT script:** Import lines that contain dates. Add new text to existing logs. Skip duplicate imports and recover interrupted log changes.

## 简体中文

用 Markdown 记录每日学习与开发进度，按日期保存到 `logs/YYYY/YYYY-MM-DD.md`。

- **交互脚本：** 手动输入一个或多个日期的日志。
- **TXT 脚本：** 提取 TXT 中含日期的行，追加到已有日志、跳过重复导入，并支持中断恢复。

## 日本語

学習と開発の進捗を Markdown で記録します。日付ごとに `logs/YYYY/YYYY-MM-DD.md` に保存します。

- **対話スクリプト：** 1 日または複数の日付の記録を入力します。
- **TXT スクリプト：** TXT の日付を含む行を取り込みます。既存ログに追記し、重複を防ぎ、中断後の変更を復旧します。

## Usage / 使用 / 使い方

**Requirements:** macOS, Git, GitHub CLI (`gh`), Python 3. Edit the script settings and run `gh auth login` first.

`bash daily-progress-interactive.sh`

`bash daily-progress.sh progress.txt`

`bash daily-progress.sh --recover-only`

> Do not add passwords or tokens to logs. The scripts set commit dates to log dates; these dates do not prove when work took place.
