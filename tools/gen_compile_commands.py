#!/usr/bin/env python3
"""Extract Makefile commands without building; adapt them for clangd.

Only kernel C translation units are included. tools/build.c is a hosted
historical Linux program and needs a separate matching userspace toolchain.
This database is for source navigation, not for producing a bootable kernel.
"""

import json
from pathlib import Path
import shlex
import shutil
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    compiler = shutil.which("clang") or "clang"
    obsolete = {"-fstrength-reduce", "-fcombine-regs", "-mstring-insns"}
    sources = sorted(p for folder in ("init", "kernel", "mm", "fs", "lib")
                     for p in (root / folder).rglob("*.c"))
    entries = []
    for source in sources:
        directory = root if source.parent.name == "init" else source.parent
        relative = source.relative_to(directory)
        target = str(relative.with_suffix(".o"))
        result = subprocess.run(
            ["make", "-Bn", "--no-print-directory", target],
            cwd=directory, check=True, capture_output=True, text=True,
        )
        commands = []
        for line in result.stdout.replace("\\\n", " ").splitlines():
            args = shlex.split(line)
            if "-c" in args and str(relative) in args:
                commands.append(args)
        if len(commands) != 1:
            raise RuntimeError(f"Expected one C compile command for {source}: {commands}")
        args = commands[0]
        args = [compiler, "--target=i386-unknown-linux-gnu", "-std=gnu89",
                "-ffreestanding"] + [arg for arg in args[1:] if arg not in obsolete]
        entries.append({"directory": str(directory), "file": str(source),
                        "arguments": args})
    output = root / "compile_commands.json"
    output.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {len(entries)} kernel C entries to {output}")


if __name__ == "__main__":
    main()
