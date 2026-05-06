#!/usr/bin/env python3
"""
sing-box Web 管理面板后端
提供 API 接口 + 静态文件服务，监听 0.0.0.0:8080
"""

import json
import os
import platform
import re
import socket
import subprocess
import time
from pathlib import Path
from threading import Thread

from flask import Flask, jsonify, request, send_from_directory

# ── 路径配置 ──────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"
SERVICE_NAME = "mysingbox"

app = Flask(__name__, static_folder=str(BASE_DIR))


# ══════════════════════════════════════════════════════════
#  静态文件服务
# ══════════════════════════════════════════════════════════

@app.route("/")
def index():
    return send_from_directory(str(BASE_DIR), "index.html")


@app.route("/<path:filename>")
def static_files(filename):
    if os.path.isfile(BASE_DIR / filename):
        return send_from_directory(str(BASE_DIR), filename)
    return ("Not Found", 404)


# ══════════════════════════════════════════════════════════
#  系统状态 API
# ══════════════════════════════════════════════════════════

@app.route("/api/stats")
def api_stats():
    cpu = _get_cpu_percent()
    mem = _get_mem_info()
    return jsonify({
        "os": f"{platform.system()} {platform.release()}",
        "platform": platform.machine(),
        "cpu_percent": cpu,
        "mem_total": mem["total"],
        "mem_used": mem["used"],
        "mem_percent": mem["percent"],
    })


# ══════════════════════════════════════════════════════════
#  统一 Action API
# ══════════════════════════════════════════════════════════

@app.route("/api/action", methods=["POST"])
def api_action():
    body = request.get_json(force=True)
    action = body.get("action", "")
    payload = body.get("payload", {})

    dispatch = {
        "get_data":           _action_get_data,
        "apply_config":       _action_apply_config,
        "add_parsed_nodes":   _action_add_parsed_nodes,
        "batch_add_socks":    _action_batch_add_socks,
        "delete_node":        _action_delete_node,
        "batch_delete_nodes": _action_batch_delete_nodes,
        "edit_node":          _action_edit_node,
        "add_devices":        _action_add_devices,
        "change_proxy":       _action_change_proxy,
        "delete_device":      _action_delete_device,
        "edit_device":        _action_edit_device,
        "update_dns":         _action_update_dns,
        "test_node":          _action_test_node,
    }

    handler = dispatch.get(action)
    if not handler:
        return jsonify({"status": "error", "message": f"未知 action: {action}"})

    try:
        return jsonify(handler(payload))
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})


# ── 读写 config.json ─────────────────────────────────────

def _load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_config(cfg):
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)


# ── Action 实现 ──────────────────────────────────────────

SYSTEM_OUTBOUND_TAGS = {"direct", "block"}
SYSTEM_RULE_ACTIONS = {"sniff", "hijack-dns"}


def _extract_nodes(cfg):
    """从 outbounds 提取用户代理节点（排除 direct/block）"""
    return [o for o in cfg.get("outbounds", []) if o.get("tag") not in SYSTEM_OUTBOUND_TAGS]


def _extract_device_rules(cfg):
    """提取带 source_ip_cidr 的路由规则（设备分流规则）"""
    rules = []
    for r in cfg.get("route", {}).get("rules", []):
        if "source_ip_cidr" in r and r.get("outbound"):
            rules.append(r)
    return rules


def _action_get_data(_payload):
    cfg = _load_config()
    nodes = _extract_nodes(cfg)
    device_rules = _extract_device_rules(cfg)

    dns_server = ""
    servers = cfg.get("dns", {}).get("servers", [])
    if servers:
        dns_server = servers[0].get("server", "")

    return {"nodes": nodes, "rules": device_rules, "dns": dns_server}


def _action_apply_config(_payload):
    try:
        result = subprocess.run(
            ["systemctl", "restart", SERVICE_NAME],
            capture_output=True, text=True, timeout=15,
        )
        if result.returncode == 0:
            return {"status": "success"}
        return {"status": "error", "message": result.stderr.strip()}
    except subprocess.TimeoutExpired:
        return {"status": "error", "message": "重启超时"}


def _action_add_parsed_nodes(payload):
    nodes = payload.get("nodes", [])
    if not nodes:
        return {"status": "error", "message": "无节点"}

    cfg = _load_config()
    existing_tags = {o["tag"] for o in cfg["outbounds"]}

    added = 0
    for node in nodes:
        tag = node.get("tag", "")
        if not tag or tag in existing_tags:
            tag = _unique_tag(tag or "node", existing_tags)
            node["tag"] = tag
        cfg["outbounds"].append(node)
        existing_tags.add(tag)
        added += 1

    _save_config(cfg)
    return {"status": "success", "added": added}


def _action_batch_add_socks(payload):
    text = payload.get("socks_text", "")
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    if not lines:
        return {"status": "error", "message": "无内容"}

    cfg = _load_config()
    existing_tags = {o["tag"] for o in cfg["outbounds"]}
    added = 0

    for line in lines:
        node = _parse_socks_line(line)
        if not node:
            continue
        tag = node.get("tag", "socks-node")
        if tag in existing_tags:
            tag = _unique_tag(tag, existing_tags)
            node["tag"] = tag
        cfg["outbounds"].append(node)
        existing_tags.add(tag)
        added += 1

    _save_config(cfg)
    return {"status": "success", "added": added}


def _action_delete_node(payload):
    tag = payload.get("tag", "")
    cfg = _load_config()
    cfg["outbounds"] = [o for o in cfg["outbounds"] if o.get("tag") != tag]
    _cleanup_rules_for_tag(cfg, tag)
    _save_config(cfg)
    return {"status": "success"}


def _action_batch_delete_nodes(payload):
    tags = set(payload.get("tags", []))
    cfg = _load_config()
    cfg["outbounds"] = [o for o in cfg["outbounds"] if o.get("tag") not in tags]
    for tag in tags:
        _cleanup_rules_for_tag(cfg, tag)
    _save_config(cfg)
    return {"status": "success"}


def _action_edit_node(payload):
    node_data = payload.get("node", {})
    tag = node_data.get("tag", "")
    cfg = _load_config()

    for o in cfg["outbounds"]:
        if o.get("tag") == tag:
            o["server"] = node_data.get("server", o.get("server"))
            o["server_port"] = node_data.get("server_port", o.get("server_port"))
            if node_data.get("username"):
                o["username"] = node_data["username"]
            elif "username" in o and not node_data.get("username"):
                o.pop("username", None)
            if node_data.get("password"):
                o["password"] = node_data["password"]
            elif "password" in o and not node_data.get("password"):
                o.pop("password", None)
            break

    _save_config(cfg)
    return {"status": "success"}


def _action_add_devices(payload):
    tag = payload.get("tag", "") or "block"
    ips = payload.get("ips", [])
    if not ips:
        return {"status": "error", "message": "无 IP"}

    cfg = _load_config()
    rules = cfg.setdefault("route", {}).setdefault("rules", [])

    existing_rule = None
    for r in rules:
        if r.get("outbound") == tag and "source_ip_cidr" in r:
            existing_rule = r
            break

    if existing_rule:
        existing_ips = set(existing_rule["source_ip_cidr"])
        for ip in ips:
            existing_ips.add(ip.strip())
        existing_rule["source_ip_cidr"] = sorted(existing_ips)
    else:
        insert_idx = _find_device_rule_insert_index(rules)
        rules.insert(insert_idx, {
            "source_ip_cidr": sorted(set(ip.strip() for ip in ips)),
            "outbound": tag,
        })

    _save_config(cfg)
    return {"status": "success"}


def _action_change_proxy(payload):
    tag = payload.get("tag", "block")
    ip = payload.get("ip", "")
    if not ip:
        return {"status": "error", "message": "无 IP"}

    cfg = _load_config()
    rules = cfg.get("route", {}).get("rules", [])

    for r in rules:
        if "source_ip_cidr" in r and ip in r["source_ip_cidr"]:
            r["source_ip_cidr"].remove(ip)

    _remove_empty_device_rules(rules)

    existing_rule = None
    for r in rules:
        if r.get("outbound") == tag and "source_ip_cidr" in r:
            existing_rule = r
            break

    if existing_rule:
        existing_rule["source_ip_cidr"].append(ip)
        existing_rule["source_ip_cidr"] = sorted(set(existing_rule["source_ip_cidr"]))
    else:
        insert_idx = _find_device_rule_insert_index(rules)
        rules.insert(insert_idx, {"source_ip_cidr": [ip], "outbound": tag})

    _save_config(cfg)
    return {"status": "success"}


def _action_delete_device(payload):
    ip = payload.get("ip", "")
    cfg = _load_config()
    rules = cfg.get("route", {}).get("rules", [])

    for r in rules:
        if "source_ip_cidr" in r and ip in r["source_ip_cidr"]:
            r["source_ip_cidr"].remove(ip)

    _remove_empty_device_rules(rules)
    _save_config(cfg)
    return {"status": "success"}


def _action_edit_device(payload):
    old_ip = payload.get("ip", "")
    new_ip = payload.get("new_ip", "").strip()
    tag = payload.get("tag", "block")

    cfg = _load_config()
    rules = cfg.get("route", {}).get("rules", [])

    for r in rules:
        if "source_ip_cidr" in r and old_ip in r["source_ip_cidr"]:
            r["source_ip_cidr"].remove(old_ip)

    _remove_empty_device_rules(rules)

    existing_rule = None
    for r in rules:
        if r.get("outbound") == tag and "source_ip_cidr" in r:
            existing_rule = r
            break

    if existing_rule:
        existing_rule["source_ip_cidr"].append(new_ip)
        existing_rule["source_ip_cidr"] = sorted(set(existing_rule["source_ip_cidr"]))
    else:
        insert_idx = _find_device_rule_insert_index(rules)
        rules.insert(insert_idx, {"source_ip_cidr": [new_ip], "outbound": tag})

    _save_config(cfg)
    return {"status": "success"}


def _action_update_dns(payload):
    dns = payload.get("dns", "")
    if not dns:
        return {"status": "error", "message": "DNS 为空"}

    cfg = _load_config()
    servers = cfg.setdefault("dns", {}).setdefault("servers", [])
    if servers:
        servers[0]["server"] = dns
    else:
        servers.append({"tag": "dns-main", "type": "udp", "server": dns})

    _save_config(cfg)
    return {"status": "success"}


def _action_test_node(payload):
    server = payload.get("server", "")
    port = int(payload.get("port", 0))
    if not server or not port:
        return {"status": "error", "message": "缺少 server/port"}

    try:
        start = time.time()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((server, port))
        latency = int((time.time() - start) * 1000)
        sock.close()
        return {"status": "success", "latency": latency}
    except Exception:
        return {"status": "error", "latency": -1}


# ── 辅助函数 ─────────────────────────────────────────────

def _unique_tag(base, existing):
    if base not in existing:
        return base
    i = 2
    while f"{base}-{i}" in existing:
        i += 1
    return f"{base}-{i}"


def _cleanup_rules_for_tag(cfg, tag):
    """删除节点后，将其关联的设备规则切到 block"""
    rules = cfg.get("route", {}).get("rules", [])
    for r in rules:
        if r.get("outbound") == tag and "source_ip_cidr" in r:
            r["outbound"] = "block"
    _merge_block_rules(rules)


def _merge_block_rules(rules):
    """合并多个 outbound=block 的 source_ip_cidr 规则"""
    block_ips = []
    to_remove = []
    for i, r in enumerate(rules):
        if r.get("outbound") == "block" and "source_ip_cidr" in r:
            block_ips.extend(r["source_ip_cidr"])
            to_remove.append(i)

    for i in reversed(to_remove):
        rules.pop(i)

    if block_ips:
        insert_idx = _find_device_rule_insert_index(rules)
        rules.insert(insert_idx, {
            "source_ip_cidr": sorted(set(block_ips)),
            "outbound": "block",
        })


def _remove_empty_device_rules(rules):
    to_remove = [i for i, r in enumerate(rules) if "source_ip_cidr" in r and len(r["source_ip_cidr"]) == 0]
    for i in reversed(to_remove):
        rules.pop(i)


def _find_device_rule_insert_index(rules):
    """在系统规则（sniff/hijack-dns）之后插入设备规则"""
    for i, r in enumerate(rules):
        if "source_ip_cidr" in r:
            return i
    for i, r in enumerate(rules):
        if r.get("action") not in SYSTEM_RULE_ACTIONS:
            return i
    return len(rules)


def _parse_socks_line(line):
    """解析多种格式的 socks5 文本行"""
    line = line.strip()
    if not line:
        return None

    # socks5://user:pass@host:port#tag
    m = re.match(r"socks5?://(?:([^:]+):([^@]+)@)?([^:/#]+):(\d+)(?:#(.+))?", line)
    if m:
        node = {"type": "socks", "tag": m.group(5) or f"socks-{m.group(3)}",
                "server": m.group(3), "server_port": int(m.group(4))}
        if m.group(1):
            node["username"] = m.group(1)
            node["password"] = m.group(2)
        return node

    # host:port:user:pass  or  host:port
    parts = line.split(":")
    if len(parts) >= 2:
        node = {"type": "socks", "tag": f"socks-{parts[0]}",
                "server": parts[0], "server_port": int(parts[1])}
        if len(parts) >= 4:
            node["username"] = parts[2]
            node["password"] = ":".join(parts[3:])
        return node

    return None


# ── 系统信息采集 ─────────────────────────────────────────

def _get_cpu_percent():
    try:
        with open("/proc/stat") as f:
            a = list(map(int, f.readline().split()[1:]))
        time.sleep(0.1)
        with open("/proc/stat") as f:
            b = list(map(int, f.readline().split()[1:]))
        delta = [b[i] - a[i] for i in range(len(a))]
        idle = delta[3]
        total = sum(delta)
        return round((1 - idle / total) * 100, 1) if total else 0
    except Exception:
        return 0


def _get_mem_info():
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                key = parts[0].rstrip(":")
                info[key] = int(parts[1]) * 1024
        total = info.get("MemTotal", 0)
        available = info.get("MemAvailable", info.get("MemFree", 0))
        used = total - available
        pct = round(used / total * 100, 1) if total else 0
        return {"total": total, "used": used, "percent": pct}
    except Exception:
        return {"total": 0, "used": 0, "percent": 0}


# ══════════════════════════════════════════════════════════
#  启动
# ══════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"[server] 配置文件: {CONFIG_PATH}")
    print(f"[server] Web 面板: http://0.0.0.0:8080")
    app.run(host="0.0.0.0", port=8080)
