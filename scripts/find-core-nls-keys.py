import argparse
import fnmatch
import json
import os
import re
import shutil
import sys
from typing import Iterable, List, Tuple


def _normalize_message(s: str) -> str:
    return s.replace("&", "").replace("...", "…")


def _get_vscode_app_root() -> str:
    code_path = shutil.which("code.cmd") or shutil.which("code")
    if not code_path:
        raise RuntimeError("未找到 code 或 code.cmd，请确认 VS Code 已安装且在 PATH 中可用。")

    bin_dir = os.path.dirname(os.path.abspath(code_path))
    install_root = os.path.realpath(os.path.join(bin_dir, ".."))

    hash_dirs: List[str] = []
    for name in os.listdir(install_root):
        full = os.path.join(install_root, name)
        if os.path.isdir(full) and re.fullmatch(r"[0-9a-f]{8,}", name):
            hash_dirs.append(full)

    if not hash_dirs:
        raise RuntimeError(f"无法在 {install_root} 下找到版本目录（形如 hash 的文件夹）。")

    hash_dirs.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    app_root = os.path.join(hash_dirs[0], "resources", "app")
    if not os.path.isdir(app_root):
        raise RuntimeError(f"找不到 VS Code appRoot：{app_root}")
    return app_root


def _iter_core_nls_messages(app_root: str) -> Iterable[Tuple[str, str, str]]:
    keys_path = os.path.join(app_root, "out", "nls.keys.json")
    msgs_path = os.path.join(app_root, "out", "nls.messages.json")

    with open(keys_path, "r", encoding="utf-8") as f:
        keys = json.load(f)
    with open(msgs_path, "r", encoding="utf-8") as f:
        msgs = json.load(f)

    i = 0
    for module, module_keys in keys:
        for k in module_keys:
            yield module, k, msgs[i]
            i += 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Find VS Code core NLS keys by matching English UI strings.")
    ap.add_argument("text", nargs="+", help="One or more query strings")
    ap.add_argument("--contains", action="store_true", help="Match by substring containment")
    ap.add_argument("--wildcard", action="store_true", help="Match by fnmatch wildcard")
    ap.add_argument("--normalize", action="store_true", help="Normalize: strip '&' and map '...' -> '…'")
    ap.add_argument("--max", type=int, default=30, help="Max results per query")
    ap.add_argument("--as-patch-template", action="store_true", help="Emit patch template rows")
    args = ap.parse_args()

    app_root = _get_vscode_app_root()
    rows = list(_iter_core_nls_messages(app_root))

    def norm(s: str) -> str:
        return _normalize_message(s) if args.normalize else s

    for q_raw in args.text:
        q = norm(q_raw)
        print(f"=== QUERY: {q_raw} ===")

        hits: List[Tuple[str, str, str]] = []
        for module, key, msg in rows:
            m = norm(msg)
            ok = False
            if args.contains:
                ok = q in m
            elif args.wildcard:
                ok = fnmatch.fnmatch(m, q)
            else:
                ok = m == q
            if ok:
                hits.append((module, key, msg))

        if not hits:
            print("  (no match)")
            continue

        for module, key, msg in hits[: args.max]:
            if args.as_patch_template:
                print(f"@{{ module='{module}'; key='{key}'; value='' }}, # raw={msg}")
            else:
                print(f"  {module}::{key}  raw=[{msg}]")

        if len(hits) > args.max:
            print(f"  (truncated to max={args.max})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
