#!/usr/bin/env bash
# 生成 FlashCount.xcodeproj。
#
# 直接跑 `xcodegen generate` 在没有 project.local.yml 的机器上会失败：
# project.yml 用 include 引入这个本机私有覆盖文件（Release 签名的
# DEVELOPMENT_TEAM），而 XcodeGen 的 include **不支持可选**——`optional: true`
# 这类键会被静默忽略，缺文件就直接报 "couldn't be opened because there is
# no such file" 并以退出码 0 结束（既不生成工程，也不明显失败）。
#
# 这正是 2026-07-26 起 CI 连续失败的原因，也会让任何新克隆在第一步就卡住。
# 所以这里在文件缺失时补一个只有注释的占位版本，再交给 XcodeGen。
set -euo pipefail

cd "$(dirname "$0")/.."

LOCAL_SPEC="project.local.yml"

if [ ! -f "$LOCAL_SPEC" ]; then
    cat > "$LOCAL_SPEC" <<'PLACEHOLDER'
# 本机私有配置 — 不入库（见 .gitignore）。
# 由 scripts/generate-project.sh 在文件缺失时自动创建。
#
# 需要用 Release 配置做真机签名时，在这里填自己的开发者团队：
#
# targets:
#   FlashCount:
#     settings:
#       configs:
#         Release:
#           DEVELOPMENT_TEAM: YOURTEAMID
PLACEHOLDER
    echo "note: 已创建占位的 ${LOCAL_SPEC}（本机私有，不入库）"
fi

exec xcodegen generate "$@"
