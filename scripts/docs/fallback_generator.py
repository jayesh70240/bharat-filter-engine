import re


def generate(analysis):
    changelog = {
        "Added": [],
        "Changed": [],
        "Fixed": [],
        "Removed": []
    }

    added = [
        item["file"]
        for item in analysis["lib_files"]
        if item["status"].startswith("A")
    ]

    modified = [
        item["file"]
        for item in analysis["lib_files"]
        if item["status"].startswith(("M", "R"))
    ]

    removed = [
        item["file"]
        for item in analysis["lib_files"]
        if item["status"].startswith("D")
    ]

    symbols = set(re.findall(
        r"^\+\s*(?:def|class|module)\s+([A-Za-z_][\w!?=]*)",
        analysis["lib_diff"],
        re.MULTILINE
    ))

    if added:
        changelog["Added"].append(
            "Added implementation files: "
            + ", ".join(f"`{file}`" for file in added)
            + "."
        )

    if modified:
        changelog["Changed"].append(
            "Updated implementation in: "
            + ", ".join(f"`{file}`" for file in modified)
            + "."
        )

    if symbols:
        changelog["Changed"].append(
            "Updated or introduced Ruby methods/classes: "
            + ", ".join(f"`{symbol}`" for symbol in sorted(symbols)[:15])
            + "."
        )

    if removed:
        changelog["Removed"].append(
            "Removed implementation files: "
            + ", ".join(f"`{file}`" for file in removed)
            + "."
        )

    return {
        "highlights": [],
        "changelog": changelog
    }
