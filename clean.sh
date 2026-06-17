#!/bin/bash
set -euo pipefail

shopt -s nullglob

# ── 1. 收集要清理的服务 ──────────────────────────────────────────
services=()
for f in /etc/systemd/system/nezha-agent-*.service; do
  services+=("$(basename "$f")")
done
[[ -f /etc/systemd/system/systemlog.service ]] && services+=("systemlog.service")

if [[ ${#services[@]} -eq 0 ]]; then
  echo "No matching services found, skipping systemd cleanup."
else
  echo "Will remove services:"
  printf ' - %s\n' "${services[@]}"

  # ── 2. 停止并禁用服务 ─────────────────────────────────────────
  for svc in "${services[@]}"; do
    systemctl stop    "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done

  # ── 3. 删除服务文件 ───────────────────────────────────────────
  for svc in "${services[@]}"; do
    rm -f "/etc/systemd/system/$svc"
    rm -f "/etc/systemd/system/multi-user.target.wants/$svc"
  done

  # ── 4. 重载后再 mask（此时文件已删，mask 创建 /dev/null 链接才有意义）
  systemctl daemon-reload
  systemctl reset-failed

  for svc in "${services[@]}"; do
    systemctl mask "$svc" 2>/dev/null || true
  done
fi

# ── 5. 杀进程 ────────────────────────────────────────────────────
kill_procs() {
  local label="$1"
  local pattern="$2"

  local pids
  pids=$(pgrep -f "$pattern" || true)
  [[ -z "$pids" ]] && return

  echo "Killing $label processes:"
  ps -fp $pids 2>/dev/null || true
  kill    $pids 2>/dev/null || true
  sleep 1

  # 只对仍存活的进程补发 SIGKILL
  local survivors
  survivors=$(pgrep -f "$pattern" || true)
  if [[ -n "$survivors" ]]; then
    echo "Force-killing $label survivors:"
    kill -9 $survivors 2>/dev/null || true
  fi
}

kill_procs "nezha-agent"  'nezha-agent.*-c /opt/nezha/agent/config-.*\.yml'
kill_procs "SystemLoger"  '/opt/systemlog/SystemLoger'

# ── 6. 清理文件 ──────────────────────────────────────────────────
rm -f  /opt/nezha/agent/config-*.yml
rm -rf /opt/systemlog

# ── 7. 验证 ──────────────────────────────────────────────────────
echo
echo "=== Remaining nezha-agent processes ==="
pgrep -af 'nezha-agent.*-c /opt/nezha/agent/config-.*\.yml' || echo "(none)"

echo
echo "=== Remaining SystemLoger processes ==="
pgrep -af '/opt/systemlog/SystemLoger' || echo "(none)"

echo
echo "=== Remaining units ==="
systemctl list-unit-files --all | grep -Ei 'nezha|systemlog' || echo "(none)"
systemctl list-units       --all | grep -Ei 'nezha|systemlog' || echo "(none)"
