#!/bin/bash
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-aimod-cc/Agent2API}"
UPSTREAM_CHANNEL="${UPSTREAM_CHANNEL:-beta}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

case "${UPSTREAM_CHANNEL}" in
    beta|stable) ;;
    *)
        printf 'Invalid UPSTREAM_CHANNEL: %s (expected beta or stable)\n' "${UPSTREAM_CHANNEL}" >&2
        exit 1
        ;;
esac

for command in curl jq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "${command}" >&2
        exit 1
    fi
done

WORK="$(mktemp "${TMPDIR:-/tmp}/agent2api-release.XXXXXX")"
trap 'rm -f "${WORK}"' EXIT

CURL_ARGS=(
    -fsSL
    --retry 5
    --retry-delay 3
    --retry-all-errors
    --connect-timeout 30
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
)
if [ -n "${TOKEN}" ]; then
    CURL_ARGS+=(-H "Authorization: Bearer ${TOKEN}")
fi

curl "${CURL_ARGS[@]}" \
    "https://api.github.com/repos/${UPSTREAM_REPO}/releases?per_page=50" \
    -o "${WORK}"

release="$(jq -c --arg channel "${UPSTREAM_CHANNEL}" '
    def has_asset($name): any(.assets[]?; .name == $name);
    [
        .[]
        | select(.draft == false)
        | select(
            if $channel == "beta" then
                .prerelease == true and (.tag_name | test("-beta\\.[0-9.]+$"))
            else
                .prerelease == false
            end
        )
        | select(
            has_asset("agent2api-server-linux-amd64.tar.gz")
            and has_asset("agent2api-server-linux-amd64.tar.gz.sha256")
            and has_asset("agent2api-server-linux-arm64.tar.gz")
            and has_asset("agent2api-server-linux-arm64.tar.gz.sha256")
        )
    ][0] // empty
' "${WORK}")"

if [ -z "${release}" ]; then
    printf 'No matching release found for %s (%s)\n' "${UPSTREAM_REPO}" "${UPSTREAM_CHANNEL}" >&2
    exit 1
fi

TAG="$(jq -r '.tag_name' <<<"${release}")"
VERSION="${TAG#v}"
RELEASE_URL="$(jq -r '.html_url' <<<"${release}")"

case "${VERSION}" in
    ''|*[!0-9A-Za-z.+-]*)
        printf 'Invalid upstream version: %s\n' "${VERSION}" >&2
        exit 1
        ;;
esac

printf 'VERSION=%s\n' "${VERSION}"
printf 'TAG=%s\n' "${TAG}"
printf 'RELEASE_URL=%s\n' "${RELEASE_URL}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        printf 'version=%s\n' "${VERSION}"
        printf 'tag=%s\n' "${TAG}"
        printf 'release_url=%s\n' "${RELEASE_URL}"
    } >> "${GITHUB_OUTPUT}"
fi
