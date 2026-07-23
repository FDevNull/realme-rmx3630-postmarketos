#!/usr/bin/env python3
"""Print a dependency-first module list for selected Android kernel modules."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("modules_dep", type=Path)
    parser.add_argument("targets", nargs="+")
    args = parser.parse_args()

    dependencies: dict[str, list[str]] = {}
    for line in args.modules_dep.read_text().splitlines():
        module_path, separator, dependency_text = line.partition(":")
        if not separator:
            continue
        dependencies[Path(module_path).name] = [
            Path(item).name for item in dependency_text.split()
        ]

    visiting: set[str] = set()
    emitted: set[str] = set()
    output: list[str] = []

    def visit(module: str) -> None:
        if module in emitted:
            return
        if module in visiting:
            raise SystemExit(f"Dependency cycle at {module}")
        if module not in dependencies:
            raise SystemExit(f"Module not present in modules.dep: {module}")
        visiting.add(module)
        for dependency in dependencies[module]:
            visit(dependency)
        visiting.remove(module)
        emitted.add(module)
        output.append(module)

    for target in args.targets:
        visit(target)

    print("\n".join(output))


if __name__ == "__main__":
    main()
