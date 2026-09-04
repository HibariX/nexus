#!/usr/bin/env python3
"""MyRaycast 随机密码插件：解析参数并用系统安全随机源生成密码。"""

from __future__ import annotations

import json
import secrets
import shlex
import string
import sys
from dataclasses import asdict, dataclass


SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?"


@dataclass(frozen=True)
class Options:
    length: int = 20
    letters: bool = True
    numbers: bool = True
    symbols: bool = True


def emit(value: dict) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def parse_bool(raw: str) -> bool:
    value = raw.strip().lower()
    if value in {"1", "true", "yes", "on", "有", "是", "开启"}:
        return True
    if value in {"0", "false", "no", "off", "无", "否", "关闭"}:
        return False
    raise ValueError(f"无法识别开关值「{raw}」")


def parse_options(query: str) -> Options:
    values = asdict(Options())
    try:
        tokens = shlex.split(query)
    except ValueError as error:
        raise ValueError(f"参数格式错误：{error}") from error

    enable = {
        "letters": ("letters", True), "letter": ("letters", True), "字母": ("letters", True),
        "numbers": ("numbers", True), "number": ("numbers", True), "digits": ("numbers", True),
        "数字": ("numbers", True),
        "symbols": ("symbols", True), "symbol": ("symbols", True), "符号": ("symbols", True),
        "no-letters": ("letters", False), "无字母": ("letters", False),
        "no-numbers": ("numbers", False), "no-digits": ("numbers", False), "无数字": ("numbers", False),
        "no-symbols": ("symbols", False), "无符号": ("symbols", False),
    }
    keys = {
        "length": "length", "len": "length", "长度": "length",
        "letters": "letters", "letter": "letters", "字母": "letters",
        "numbers": "numbers", "number": "numbers", "digits": "numbers", "数字": "numbers",
        "symbols": "symbols", "symbol": "symbols", "符号": "symbols",
    }

    for token in tokens:
        lower = token.lower()
        if lower.isdecimal():
            values["length"] = int(lower)
            continue
        if lower in enable:
            key, enabled = enable[lower]
            values[key] = enabled
            continue
        if "=" in lower:
            raw_key, raw_value = lower.split("=", 1)
            key = keys.get(raw_key)
            if key == "length":
                try:
                    values[key] = int(raw_value)
                except ValueError as error:
                    raise ValueError("长度必须是整数") from error
                continue
            if key:
                values[key] = parse_bool(raw_value)
                continue
        raise ValueError(f"未知参数「{token}」")

    options = Options(**values)
    validate_options(options)
    return options


def validate_options(options: Options) -> None:
    if not 4 <= options.length <= 256:
        raise ValueError("长度范围为 4–256")
    if not (options.letters or options.numbers or options.symbols):
        raise ValueError("字母、数字、符号至少启用一项")
    required = (2 if options.letters else 0) + int(options.numbers) + int(options.symbols)
    if options.length < required:
        raise ValueError(f"当前字符组合至少需要 {required} 位")


def describe(options: Options) -> str:
    parts = []
    if options.letters:
        parts.append("大小写字母")
    if options.numbers:
        parts.append("数字")
    if options.symbols:
        parts.append("符号")
    return " · ".join(parts)


def generate(options: Options) -> str:
    groups: list[str] = []
    password: list[str] = []
    if options.letters:
        groups.extend([string.ascii_lowercase, string.ascii_uppercase])
        password.extend([secrets.choice(string.ascii_lowercase), secrets.choice(string.ascii_uppercase)])
    if options.numbers:
        groups.append(string.digits)
        password.append(secrets.choice(string.digits))
    if options.symbols:
        groups.append(SYMBOLS)
        password.append(secrets.choice(SYMBOLS))

    alphabet = "".join(groups)
    password.extend(secrets.choice(alphabet) for _ in range(options.length - len(password)))
    secrets.SystemRandom().shuffle(password)
    return "".join(password)


def generation_item(options: Options, title: str | None = None) -> dict:
    return {
        "title": title or f"生成 {options.length} 位密码",
        "subtitle": describe(options),
        "icon": "key.fill",
        "hint": "⏎ 生成并复制",
        "action": "generate",
        "payload": json.dumps(asdict(options), separators=(",", ":")),
    }


def query_items(query: str) -> None:
    if not query.strip():
        presets = [
            generation_item(Options(), "生成默认密码（20 位）"),
            generation_item(Options(length=16, symbols=False), "生成 16 位无符号密码"),
            generation_item(Options(length=24), "生成 24 位强密码"),
            generation_item(Options(length=32), "生成 32 位强密码"),
            {
                "title": "自定义参数示例：24 symbols=off letters=on numbers=on",
                "subtitle": "长度 4–256；开关可用 on/off，也支持 no-symbols、无符号",
                "icon": "slider.horizontal.3",
            },
        ]
        emit({"items": presets})
        return

    try:
        options = parse_options(query)
        emit({"items": [generation_item(options)]})
    except ValueError as error:
        emit({"items": [{
            "title": f"参数错误：{error}",
            "subtitle": "示例：24 symbols=off letters=on numbers=on",
            "icon": "exclamationmark.triangle",
        }]})


def perform_action(action: str, payload: str) -> None:
    if action != "generate":
        emit({})
        return
    try:
        raw = json.loads(payload)
        if not isinstance(raw, dict):
            raise ValueError("payload 必须是对象")
        length = raw.get("length", 20)
        if type(length) is not int:
            raise ValueError("长度必须是整数")
        flags = {}
        for key in ("letters", "numbers", "symbols"):
            value = raw.get(key, True)
            if type(value) is not bool:
                raise ValueError(f"{key} 必须是布尔值")
            flags[key] = value
        options = Options(
            length=length,
            letters=flags["letters"],
            numbers=flags["numbers"],
            symbols=flags["symbols"],
        )
        validate_options(options)
        emit({"copy": generate(options), "concealed": True, "keepOpen": False})
    except (TypeError, ValueError, json.JSONDecodeError):
        emit({"keepOpen": True})


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "query":
        query_items(sys.argv[2] if len(sys.argv) > 2 else "")
    elif command == "action":
        perform_action(
            sys.argv[2] if len(sys.argv) > 2 else "",
            sys.argv[3] if len(sys.argv) > 3 else "",
        )
    else:
        emit({"items": []})


if __name__ == "__main__":
    main()
