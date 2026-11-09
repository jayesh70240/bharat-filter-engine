import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    analysis = json.loads(
        (ROOT / "release-analysis.json").read_text(encoding="utf-8")
    )

    version = analysis["version"]

    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")

    if not analysis["has_lib_changes"]:
        raise ValueError("No lib changes found")

    if not re.search(
        rf"version-{re.escape(version)}-blue",
        readme
    ):
        raise ValueError("README version badge is outdated")

    if not re.search(
        rf"(?m)^## \[{re.escape(version)}\]",
        changelog
    ):
        raise ValueError("CHANGELOG release entry missing")

    for filename, content in (
        ("README.md", readme),
        ("CHANGELOG.md", changelog)
    ):
        if "\x00" in content:
            raise ValueError(f"Invalid content in {filename}")

        if not content.endswith("\n"):
            raise ValueError(f"{filename} must end with a newline")

    print(f"Documentation validation passed: {version}")


if __name__ == "__main__":
    main()
