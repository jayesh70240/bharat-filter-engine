import json
import re
from datetime import date
from pathlib import Path

from ai_provider import generate as ai_generate
from fallback_generator import generate as fallback_generate

ROOT = Path(__file__).resolve().parents[2]

ANALYSIS = ROOT / "release-analysis.json"
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"


def clean_items(items):
    return [
        item.strip().rstrip(".")
        for item in items
        if isinstance(item, str) and item.strip()
    ]


def load_documentation(analysis):
    try:
        result = ai_generate(analysis)
        print("Using Gemini documentation generator")
        return result
    except Exception as error:
        print(f"AI unavailable: {error}")
        print("Using Python fallback")
        return fallback_generate(analysis)


def update_readme(version, highlights):
    content = README.read_text(encoding="utf-8")

    content = re.sub(
        r"(version-)\d+\.\d+\.\d+(-blue)",
        rf"\g<1>{version}\g<2>",
        content,
        count=1
    )

    heading = f"## What's new in {version}"

    content = re.sub(
        rf"(?ms)^## What's new in \d+\.\d+\.\d+.*?(?=^## |\Z)",
        "",
        content
    )

    highlights = clean_items(highlights)

    if highlights:
        section = (
            heading
            + "\n\n"
            + "\n".join(f"- {item}" for item in highlights)
            + "\n\n"
        )

        marker = "## Installation"

        if marker not in content:
            raise ValueError("README Installation section not found")

        content = content.replace(marker, section + marker, 1)

    README.write_text(content, encoding="utf-8")


def update_changelog(version, changelog):
    content = CHANGELOG.read_text(encoding="utf-8")

    content = re.sub(
        rf"(?ms)^## \[{re.escape(version)}\].*?(?=^## \[|\Z)",
        "",
        content
    )

    sections = []

    for category in ("Added", "Changed", "Fixed", "Removed"):
        items = clean_items(changelog.get(category, []))

        if items:
            sections.append(
                f"### {category}\n\n"
                + "\n".join(f"- {item}" for item in items)
            )

    if not sections:
        sections.append(
            "### Changed\n\n"
            "- Internal implementation updates."
        )

    entry = (
        f"## [{version}] - {date.today().isoformat()}\n\n"
        + "\n\n".join(sections)
        + "\n\n"
    )

    marker = (
        "All notable changes to this project will be documented here."
    )

    if marker not in content:
        raise ValueError("CHANGELOG introduction not found")

    content = content.replace(
        marker,
        marker + "\n\n" + entry,
        1
    )

    CHANGELOG.write_text(content, encoding="utf-8")


def main():
    analysis = json.loads(
        ANALYSIS.read_text(encoding="utf-8")
    )

    if not analysis["has_lib_changes"]:
        raise ValueError("No lib changes available")

    documentation = load_documentation(analysis)

    update_readme(
        analysis["version"],
        documentation.get("highlights", [])
    )

    update_changelog(
        analysis["version"],
        documentation.get("changelog", {})
    )

    print(f"Documentation generated for {analysis['version']}")


if __name__ == "__main__":
    main()
