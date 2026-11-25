"""Deploy the exact uploaded Pages artifact through GitHub's documented REST API."""
import json
import os
import time
import urllib.error
import urllib.request


def request(url, token, payload=None):
    headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json", "User-Agent": "ToolSidebar-Pages"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode()
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=30) as response:
        return json.load(response)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("Run this script inside the Pages GitHub Actions job")
    token = os.environ["GH_TOKEN"]
    base = os.environ["GITHUB_API_URL"] + "/repos/" + os.environ["GITHUB_REPOSITORY"]
    artifact_id = int(os.environ["PAGES_ARTIFACT_ID"])
    artifact = None
    for attempt in range(12):
        try:
            artifact = request(base + "/actions/artifacts/" + str(artifact_id), token)
            break
        except urllib.error.HTTPError as error:
            if error.code not in (404, 429, 500, 502, 503) or attempt == 11:
                raise
            time.sleep(5)
    assert artifact and not artifact["expired"]
    assert artifact["name"] == os.environ["PAGES_ARTIFACT_NAME"]
    assert artifact["workflow_run"]["id"] == int(os.environ["GITHUB_RUN_ID"])
    assert artifact["workflow_run"]["head_sha"] == os.environ["GITHUB_SHA"]

    # Tokens remain in memory and are never printed or written to the artifact.
    oidc = request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"], os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"])["value"]
    deployment = request(base + "/pages/deployments", token, {
        "artifact_id": artifact_id, "pages_build_version": os.environ["GITHUB_SHA"], "oidc_token": oidc
    })
    deployment_id = str(deployment["id"])
    print("Created Pages deployment for verified artifact", artifact_id, flush=True)
    for _ in range(120):
        status = request(base + "/pages/deployments/" + deployment_id, token)["status"]
        if status == "succeed":
            url = request(base + "/pages", token)["html_url"]
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write("page_url=" + url + "\n")
            print("Pages deployment succeeded", flush=True)
            return
        if status in {"errored", "failed", "canceled", "cancelled"}:
            raise RuntimeError("Pages deployment ended with status " + status)
        time.sleep(5)
    raise TimeoutError("Pages deployment did not complete in ten minutes")


if __name__ == "__main__":
    main()
