#!/usr/bin/env python3

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def git_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        check=True,
        text=True,
    )
    return Path(result.stdout.strip())


ROOT = git_root()
MEMVID_DIR = ROOT / ".memvid"
INDEX_PATH = MEMVID_DIR / "index.mv2"
STATE_PATH = MEMVID_DIR / "state.json"
TEXT_EXTENSIONS = {
    ".c",
    ".cpp",
    ".go",
    ".h",
    ".js",
    ".json",
    ".md",
    ".nix",
    ".py",
    ".rs",
    ".sh",
    ".ts",
    ".tsx",
    ".txt",
    ".yaml",
    ".yml",
}


def run(command: list[str], *, capture_output: bool = True, check: bool = True) -> str:
    result = subprocess.run(
        command,
        capture_output=capture_output,
        check=check,
        cwd=ROOT,
        text=True,
    )
    return result.stdout.strip() if capture_output else ""


def tracked_files(include_untracked: bool) -> list[Path]:
    files = run(["git", "ls-files"]).splitlines()
    if include_untracked:
        files.extend(run(["git", "ls-files", "--others", "--exclude-standard"]).splitlines())
    return [
        ROOT / path
        for path in files
        if (ROOT / path).is_file() and (ROOT / path).suffix in TEXT_EXTENSIONS
    ]


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8192), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"files": {}, "git_head": ""}
    try:
        return json.loads(STATE_PATH.read_text())
    except json.JSONDecodeError:
        return {"files": {}, "git_head": ""}


def write_state(files: dict[str, str]) -> None:
    STATE_PATH.write_text(
        json.dumps(
            {
                "files": files,
                "git_head": run(["git", "rev-parse", "HEAD"]),
            },
            indent=2,
        )
        + "\n"
    )


def init_repo(_: argparse.Namespace) -> None:
    MEMVID_DIR.mkdir(exist_ok=True)
    if not INDEX_PATH.exists():
        run(["memvid", "create", str(INDEX_PATH), "--no-vector"], capture_output=False)


def index_repo(args: argparse.Namespace) -> None:
    init_repo(args)
    previous = load_state()
    current = {str(path.relative_to(ROOT)): file_hash(path) for path in tracked_files(args.include_untracked)}
    changed = [path for path, digest in current.items() if previous["files"].get(path) != digest]

    if not changed:
        print("Index is up to date.")
        return

    for path in changed:
        run(
            [
                "memvid",
                "put",
                str(INDEX_PATH),
                "--input",
                path,
                "--lock-timeout",
                str(args.lock_timeout),
            ],
            capture_output=False,
        )
    write_state(current)
    print(f"Indexed {len(changed)} files.")


def ensure_repo(args: argparse.Namespace) -> None:
    if not INDEX_PATH.exists() or load_state()["git_head"] != run(["git", "rev-parse", "HEAD"]):
        index_repo(args)
    else:
        print("Index is already fresh.")


def search_repo(args: argparse.Namespace) -> None:
    command = [
        "memvid",
        "find",
        str(INDEX_PATH),
        "--query",
        args.query,
        "--mode",
        args.mode,
        "--top-k",
        str(args.top_k),
    ]
    if args.json:
        command.append("--json")
    run(command, capture_output=False, check=False)


def ask_repo(args: argparse.Namespace) -> None:
    command = ["memvid", "ask", str(INDEX_PATH), "--question", args.question, "--use-model", args.model]
    if args.json:
        command.append("--json")
    run(command, capture_output=False, check=False)


def status_repo(_: argparse.Namespace) -> None:
    if not INDEX_PATH.exists():
        print("Index does not exist. Run 'repo-mem init' first.")
        return
    state = load_state()
    print(f"Index path: {INDEX_PATH}")
    print(f"Last indexed commit: {state['git_head'] or 'unknown'}")
    print(f"Indexed files: {len(state['files'])}")
    print(f"Index size: {INDEX_PATH.stat().st_size / (1024 * 1024):.2f} MiB")


def clean_repo(_: argparse.Namespace) -> None:
    for path in [INDEX_PATH, STATE_PATH]:
        path.unlink(missing_ok=True)
    try:
        MEMVID_DIR.rmdir()
    except OSError:
        pass


def visualize_repo(args: argparse.Namespace) -> None:
    init_repo(args)
    files = [path.relative_to(ROOT) for path in tracked_files(False)]
    tree: dict[str, dict] = {}
    for path in files:
        node = tree
        for part in path.parts:
            node = node.setdefault(part, {})

    def render(node: dict[str, dict], depth: int = 0) -> str:
        return "".join(
            f"{'  ' * depth}- {name}\n{render(children, depth + 1)}"
            for name, children in sorted(node.items())
        )

    artifact = MEMVID_DIR / "repository-map.md"
    artifact.write_text(f"# Repository Map\n\n```text\n{render(tree)}```\n")
    run(
        [
            "memvid",
            "put",
            str(INDEX_PATH),
            "--input",
            str(artifact),
            "--title",
            "repository-map",
            "--tag",
            "visualization",
        ],
        capture_output=False,
    )
    artifact.unlink()
    if not args.silent:
        print(render(tree), end="")


def show_repo(_: argparse.Namespace) -> None:
    run(
        ["memvid", "find", str(INDEX_PATH), "--query", "repository-map", "--top-k", "1", "--json"],
        capture_output=False,
        check=False,
    )


def parser() -> argparse.ArgumentParser:
    command_parser = argparse.ArgumentParser(description="Local Memvid index for the current Git repository")
    commands = command_parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init")

    index = commands.add_parser("index")
    index.add_argument("--include-untracked", action="store_true")
    index.add_argument("--lock-timeout", type=int, default=5000)

    ensure = commands.add_parser("ensure")
    ensure.add_argument("--include-untracked", action="store_true")
    ensure.add_argument("--lock-timeout", type=int, default=250)

    search = commands.add_parser("search")
    search.add_argument("query")
    search.add_argument("--mode", default="lex")
    search.add_argument("--top-k", type=int, default=5)
    search.add_argument("--json", action="store_true")

    ask = commands.add_parser("ask")
    ask.add_argument("question")
    ask.add_argument("--model", default="ollama:qwen2.5:1.5b")
    ask.add_argument("--json", action="store_true")

    commands.add_parser("status")
    commands.add_parser("clean")

    visualize = commands.add_parser("visualize")
    visualize.add_argument("--silent", action="store_true")

    commands.add_parser("show")
    return command_parser


def main() -> None:
    args = parser().parse_args()
    handlers = {
        "init": init_repo,
        "index": index_repo,
        "ensure": ensure_repo,
        "search": search_repo,
        "ask": ask_repo,
        "status": status_repo,
        "clean": clean_repo,
        "visualize": visualize_repo,
        "show": show_repo,
    }
    handlers[args.command](args)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error, file=sys.stderr)
        raise SystemExit(error.returncode)
