#!/usr/bin/env python3
import json
import os
import sys


def main() -> int:
    # Stop hooks receive event JSON on stdin. We don't need the payload for the
    # minimal auto-continue behavior, but parsing it keeps failures visible.
    raw = sys.stdin.read()
    if raw.strip():
        try:
            json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"invalid hook input: {exc}", file=sys.stderr)
            return 1

    prompt = os.environ.get("CODEX_AUTO_CONTINUE_TEXT", "continue!你详细对比GO版本，看看AST分析，CHECKER检查器，compile编译器，是否完全一致了？如果没有一致，记住这次差异，就像完成")
    result = {
        "decision": "block",
        "reason": prompt,
    }
    json.dump(result, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
