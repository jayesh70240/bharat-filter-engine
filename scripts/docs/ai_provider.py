import json
import os
import urllib.error
import urllib.parse
import urllib.request


MODEL = "gemini-2.5-flash"


def generate(analysis):
    api_key = os.environ.get("GEMINI_API_KEY")

    if not api_key:
        raise RuntimeError("Gemini API key not configured")

    prompt = f"""
You are documenting a Ruby gem release.

Analyze the actual Ruby source diff and supporting specs.

Only document behavior that is clearly supported by the source code.

Rules:
- Focus on public-facing features and behavior.
- Do not invent features or capabilities.
- Do not mention CI, workflows, or repository maintenance.
- Do not mention internal test file changes as user-facing features.
- Preserve existing API behavior unless the diff proves otherwise.
- Keep descriptions concise.
- Do not generate generic filler.
- Maximum 5 README highlights.
- Empty categories must be empty arrays.

Return valid JSON only:

{{
  "highlights": [],
  "changelog": {{
    "Added": [],
    "Changed": [],
    "Fixed": [],
    "Removed": []
  }}
}}

RELEASE ANALYSIS:

{json.dumps(analysis, ensure_ascii=False)}
"""

    url = (
        "https://generativelanguage.googleapis.com/v1beta/"
        f"models/{MODEL}:generateContent?"
        + urllib.parse.urlencode({"key": api_key})
    )

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "temperature": 0.2
        }
    }

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            result = json.loads(response.read())

        content = result["candidates"][0]["content"]["parts"][0]["text"]
        documentation = json.loads(content)

        if not isinstance(documentation.get("highlights"), list):
            raise ValueError("Invalid highlights")

        if not isinstance(documentation.get("changelog"), dict):
            raise ValueError("Invalid changelog")

        for category in ("Added", "Changed", "Fixed", "Removed"):
            if not isinstance(
                documentation["changelog"].get(category, []),
                list
            ):
                raise ValueError(f"Invalid category: {category}")

        return documentation

    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        KeyError,
        IndexError,
        json.JSONDecodeError
    ) as error:
        raise RuntimeError(f"Gemini API failed: {error}") from error
