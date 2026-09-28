#!/usr/bin/env python3
"""Merge managed package mirrors into a target user's existing settings."""

import os
import re
import stat
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


MAVEN_URL = "https://maven.aliyun.com/repository/public"
CARGO_URL = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def configure_maven(home: Path) -> None:
    path = home / ".m2/settings.xml"
    namespace = "http://maven.apache.org/SETTINGS/1.2.0"
    if path.exists():
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        root = ET.parse(path, parser=parser).getroot()
        if root.tag != "settings" and not root.tag.endswith("}settings"):
            raise ValueError("Maven settings.xml 根元素不是 settings")
        if root.tag.startswith("{"):
            namespace = root.tag[1:].split("}", 1)[0]
        else:
            namespace = ""
    else:
        root = ET.Element(f"{{{namespace}}}settings")
    if namespace:
        ET.register_namespace("", namespace)
    tag = lambda name: f"{{{namespace}}}{name}" if namespace else name
    mirrors = root.find(tag("mirrors"))
    if mirrors is None:
        mirrors = ET.Element(tag("mirrors"))
        root.insert(0, mirrors)
    for mirror in list(mirrors):
        if mirror.findtext(tag("id")) == "server-shell-kit-aliyun":
            mirrors.remove(mirror)
    mirror = ET.Element(tag("mirror"))
    for key, value in (
        ("id", "server-shell-kit-aliyun"),
        ("name", "Aliyun Maven Central"),
        ("url", MAVEN_URL),
        ("mirrorOf", "central"),
    ):
        ET.SubElement(mirror, tag(key)).text = value
    mirrors.insert(0, mirror)
    atomic_write(path, ET.tostring(root, encoding="utf-8", xml_declaration=True))


def set_cargo_key(text: str, section: str, key: str, value: str) -> str:
    heading = re.compile(r"(?m)^\s*\[([^\]\n]+)\]\s*$")
    matches = list(heading.finditer(text))
    target = [match for match in matches if match.group(1).strip() == section]
    if len(target) > 1:
        raise ValueError(f"Cargo 配置中重复出现 [{section}]")
    assignment = f'{key} = "{value}"\n'
    if not target:
        return text.rstrip("\n") + f"\n\n[{section}]\n" + assignment
    start = target[0].end()
    end = next((match.start() for match in matches if match.start() > start), len(text))
    body = text[start:end]
    key_pattern = re.compile(rf"(?m)^\s*{re.escape(key)}\s*=.*(?:\n|$)")
    body = key_pattern.sub("", body)
    return text[:start] + "\n" + assignment + body.lstrip("\n") + text[end:]


def configure_cargo(home: Path) -> None:
    path = home / ".cargo/config.toml"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    text = set_cargo_key(text, "source.crates-io", "replace-with", "ustc")
    text = set_cargo_key(text, "source.ustc", "registry", CARGO_URL)
    try:
        import tomllib
    except ImportError:
        pass
    else:
        tomllib.loads(text)
    atomic_write(path, text.encode("utf-8"))


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("maven", "cargo"):
        raise SystemExit("用法：configure-programming-mirror.py maven|cargo TARGET_HOME")
    home = Path(sys.argv[2])
    if sys.argv[1] == "maven":
        configure_maven(home)
    else:
        configure_cargo(home)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ET.ParseError) as exc:
        raise SystemExit(f"配置国内包源失败：{exc}") from None
