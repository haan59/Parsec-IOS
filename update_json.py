import json
import os
import plistlib
from datetime import datetime, timezone

# Rewrites altstore.json for the nightly release. Runs in CI before the release is published,
# so the download URL is built from the repo name and the size is read from the local Parsec.ipa.

IPA_NAME = "Parsec.ipa"
JSON_FILE = "altstore.json"


def main():
    repo = os.environ.get("GITHUB_REPOSITORY", "haan59/Parsec-IOS")
    commit_sha = os.environ.get("commit_sha", "")[:7]
    commit_msg = os.environ.get("commit_msg", "").strip()
    build_number = os.environ.get("BUILD_NUMBER", "")
    nightly_link = os.environ.get("NIGHTLY_LINK", "")

    with open("HanParsec/Info.plist", "rb") as f:
        version = plistlib.load(f)["CFBundleShortVersionString"]

    download_url = f"https://github.com/{repo}/releases/download/nightly/{IPA_NAME}"
    size = os.path.getsize(IPA_NAME) if os.path.exists(IPA_NAME) else 0
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    description = "Nightly build"
    if commit_sha:
        description += f" from {commit_sha}"
    if commit_msg:
        description += f": {commit_msg}"
    if nightly_link:
        description += f"\n\nBuilt by GitHub Actions: {nightly_link}"

    with open(JSON_FILE, "r") as f:
        data = json.load(f)

    app = data["apps"][0]
    entry = {
        "version": version,
        "date": date,
        "localizedDescription": description,
        "downloadURL": download_url,
        "size": size,
    }
    if build_number:
        entry["buildVersion"] = build_number

    app["versions"] = [entry]
    app.update({
        "version": version,
        "versionDate": date,
        "versionDescription": description,
        "downloadURL": download_url,
        "size": size,
    })
    data["news"] = []

    with open(JSON_FILE, "w") as f:
        json.dump(data, f, indent=2)
    print(f"{JSON_FILE} updated: {version}, {size} bytes, {download_url}")


if __name__ == "__main__":
    main()
