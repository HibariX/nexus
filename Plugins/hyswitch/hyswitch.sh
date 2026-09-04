#!/bin/bash
# hyswitch 插件：节点切换 / Claude 额度 / 隧道状态。
# 协议：
#   query "<子query>"            → {"items":[...]}   （item 可带 action=执行动作，或 query=进入子查询）
#   action "<actionId>" "<载荷>"  → {"copy":..,"reload":..,"keepOpen":..}
# 不 set -e，逐处容错，保证总能吐出合法 JSON。

HYS_DIR="$HOME/.config/hysteria"
PROFILES_DIR="$HYS_DIR/profiles"
ACTIVE_LINK="$HYS_DIR/hysteria-client.yaml"
HYSWITCH_BIN="$HOME/.local/bin/hyswitch"
QUOTA_URL="http://127.0.0.1:18318/"

cmd="${1:-}"
arg="${2:-}"      # query 时为子query；action 时为 actionId
payload="${3:-}"  # action 时为载荷（如节点名）

# ---- 额度：拿数据渲染成展示 items（首行 action=quota 可复制全文）----
quota_items() {
    local body
    body=$(curl -s -m 3 "$QUOTA_URL" 2>/dev/null || true)
    BODY="$body" python3 - <<'PY'
import json, os, time
try:
    m = json.loads(os.environ.get("BODY", ""))
    if not isinstance(m, dict): m = {}
except Exception:
    m = {}

def render(util, reset):
    try: pct = float(util) * 100
    except Exception: pct = 0.0
    n = max(0, min(10, int(pct / 10 + 0.5)))
    bar = "█" * n + "░" * (10 - n)
    rs = ""
    try:
        ts = int(reset)
        if ts > 0: rs = "重置 " + time.strftime("%m-%d %H:%M", time.localtime(ts))
    except Exception: pass
    return bar, pct, rs

u5 = m.get("anthropic-ratelimit-unified-5h-utilization", "")
if not u5:
    items = [{"title": "查不到额度", "subtitle": "隧道未通或当前节点无额度服务",
              "icon": "exclamationmark.triangle"}]
else:
    status = (m.get("anthropic-ratelimit-unified-status")
              or m.get("anthropic-ratelimit-unified-5h-status") or "")
    b5, p5, r5 = render(u5, m.get("anthropic-ratelimit-unified-5h-reset", ""))
    b7, p7, r7 = render(m.get("anthropic-ratelimit-unified-7d-utilization", ""),
                         m.get("anthropic-ratelimit-unified-7d-reset", ""))
    items = [
        {"title": "Claude 额度" + (f"  ·  {status}" if status else ""),
         "icon": "gauge", "action": "quota", "payload": "", "hint": "⏎ 复制"},
        {"title": f"5 小时窗口  {b5}  {p5:.1f}%", "subtitle": r5 or None, "icon": "clock"},
        {"title": f"7 天窗口  {b7}  {p7:.1f}%", "subtitle": r7 or None, "icon": "clock"},
    ]
for it in items:
    if it.get("subtitle") is None: it.pop("subtitle", None)
print(json.dumps({"items": items}, ensure_ascii=False))
PY
}

# ---- 状态：hyswitch status 输出（去 ANSI）逐行成展示 items ----
status_items() {
    local out=""
    if [ -x "$HYSWITCH_BIN" ]; then
        out=$("$HYSWITCH_BIN" status 2>/dev/null | sed $'s/\x1b\\[[0-9;]*m//g' || true)
    fi
    OUT="$out" python3 - <<'PY'
import json, os
lines = [l.strip() for l in os.environ.get("OUT", "").split("\n") if l.strip()]
if not lines:
    items = [{"title": "无状态输出", "icon": "exclamationmark.triangle"}]
else:
    items = []
    for i, l in enumerate(lines):
        it = {"title": l, "icon": "dot.radiowaves.left.and.right"}
        if i == 0:
            it.update({"action": "status", "payload": "", "hint": "⏎ 复制"})
        items.append(it)
print(json.dumps({"items": items}, ensure_ascii=False))
PY
}

# ---- 节点列表 + 额度/状态入口（入口用 query 进入子查询）----
node_items() {
    local filter_lower
    filter_lower=$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')

    local current=""
    if [ -L "$ACTIVE_LINK" ]; then
        current=$(basename "$(readlink "$ACTIVE_LINK")" .yaml)
    fi

    local rows=""
    if [ -d "$PROFILES_DIR" ]; then
        for f in "$PROFILES_DIR"/*.yaml; do
            [ -e "$f" ] || continue
            local name
            name=$(basename "$f" .yaml)
            if [ -n "$filter_lower" ]; then
                case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
                    *"$filter_lower"*) ;;
                    *) continue ;;
                esac
            fi
            local server
            server=$(grep -m1 -E '^[[:space:]]*server:' "$f" 2>/dev/null \
                | sed -E 's/^[[:space:]]*server:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' | tr -d '\r')
            rows+="$name"$'\t'"$server"$'\t'"$current"$'\n'
        done
    fi

    local extras
    extras=$([ -z "$filter_lower" ] && echo 1 || echo 0)

    ROWS="$rows" EXTRAS="$extras" python3 - <<'PY'
import json, os
rows = [r for r in os.environ.get("ROWS", "").split("\n") if r.strip()]
items = []
for r in rows:
    p = r.split("\t")
    name = p[0]
    server = p[1] if len(p) > 1 else ""
    current = p[2] if len(p) > 2 else ""
    cur = (name == current)
    sub = (("当前节点 · " + server) if cur else server) if server else ("当前节点" if cur else "")
    it = {"title": name, "icon": "checkmark.circle.fill" if cur else "circle",
          "hint": "⏎ 当前" if cur else "⏎ 切换", "action": "switch", "payload": name}
    if sub: it["subtitle"] = sub
    items.append(it)
if os.environ.get("EXTRAS") == "1":
    items.append({"title": "查询 Claude 额度", "icon": "gauge", "hint": "⏎ 查询", "query": "quota"})
    items.append({"title": "查看隧道状态", "icon": "dot.radiowaves.left.and.right", "hint": "⏎ 查看", "query": "status"})
print(json.dumps({"items": items}, ensure_ascii=False))
PY
}

do_switch() {
    local name="$payload"
    [ -z "$name" ] && name="$arg"
    if [ -n "$name" ] && [ -x "$HYSWITCH_BIN" ]; then
        "$HYSWITCH_BIN" "$name" >/dev/null 2>&1 || true
    fi
    echo '{"reload":true,"keepOpen":true}'
}

do_quota_copy() {
    local body
    body=$(curl -s -m 3 "$QUOTA_URL" 2>/dev/null || true)
    BODY="$body" python3 - <<'PY'
import json, os, time
try:
    m = json.loads(os.environ.get("BODY", ""))
    if not isinstance(m, dict): m = {}
except Exception:
    m = {}
def line(label, util, reset):
    try: pct = float(util) * 100
    except Exception: pct = 0.0
    n = max(0, min(10, int(pct / 10 + 0.5)))
    bar = "█" * n + "░" * (10 - n)
    rs = ""
    try:
        ts = int(reset)
        if ts > 0: rs = "  重置 " + time.strftime("%m-%d %H:%M", time.localtime(ts))
    except Exception: pass
    return f"{label} {bar} {pct:5.1f}%{rs}"
u5 = m.get("anthropic-ratelimit-unified-5h-utilization", "")
if not u5:
    print(json.dumps({"copy": "查不到额度（隧道未通或当前节点无额度服务）", "keepOpen": True}, ensure_ascii=False))
else:
    status = (m.get("anthropic-ratelimit-unified-status")
              or m.get("anthropic-ratelimit-unified-5h-status") or "")
    txt = "Claude 额度" + (f"（{status}）" if status else "") + "\n"
    txt += line("5 小时窗口", u5, m.get("anthropic-ratelimit-unified-5h-reset", "")) + "\n"
    txt += line("7 天窗口 ", m.get("anthropic-ratelimit-unified-7d-utilization", ""),
                m.get("anthropic-ratelimit-unified-7d-reset", ""))
    print(json.dumps({"copy": txt, "keepOpen": True}, ensure_ascii=False))
PY
}

do_status_copy() {
    local out=""
    if [ -x "$HYSWITCH_BIN" ]; then
        out=$("$HYSWITCH_BIN" status 2>/dev/null | sed $'s/\x1b\\[[0-9;]*m//g' || true)
    fi
    OUT="$out" python3 - <<'PY'
import json, os
print(json.dumps({"copy": os.environ.get("OUT", "").strip() or "无状态输出", "keepOpen": True}, ensure_ascii=False))
PY
}

case "$cmd" in
    query)
        case "$arg" in
            quota*)  quota_items ;;
            status*) status_items ;;
            *)       node_items ;;
        esac
        ;;
    action)
        case "$arg" in
            switch) do_switch ;;
            quota)  do_quota_copy ;;
            status) do_status_copy ;;
            *)      echo '{}' ;;
        esac
        ;;
    *)
        echo '{"items":[]}'
        ;;
esac
