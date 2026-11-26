"""Compare public symbol graph declaration paths and spellings across toolchains."""
import argparse
from collections import defaultdict
import json
from pathlib import Path


def declarations(root):
    result = defaultdict(set)
    files = [path for path in Path(root).rglob("*.symbols.json")
             if path.name.split("@")[0].split(".")[0] in {"SwiftUI", "SwiftUICore"}]
    if not files:
        raise SystemExit(f"No SwiftUI symbol graphs in {root}")
    for path in files:
        symbols = json.loads(path.read_text())["symbols"]
        for symbol in symbols:
            parts = symbol["pathComponents"]
            if any(part.startswith("_") for part in parts):
                continue
            key = (symbol["kind"]["identifier"], ".".join(parts))
            declaration = "".join(fragment["spelling"] for fragment in symbol.get("declarationFragments", []))
            result[key].add(declaration)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apple")
    parser.add_argument("linux")
    parser.add_argument("--missing", action="store_true", help="print Apple paths absent on Linux")
    args = parser.parse_args()
    apple, linux = declarations(args.apple), declarations(args.linux)
    common = apple.keys() & linux.keys()
    exact = sum(len(apple[key] & linux[key]) for key in common)
    print(f"Apple declaration paths: {len(apple)}")
    print(f"Paths also present on Linux: {len(common)}")
    print(f"Missing paths: {len(apple.keys() - common)}")
    print(f"Apple declaration spellings: {sum(map(len, apple.values()))}")
    print(f"Identical spellings at matching paths: {exact}")
    if args.missing:
        for kind, path in sorted(apple.keys() - linux.keys()):
            print(kind, path)


if __name__ == "__main__":
    main()
