#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="${ROOT}/packaging/fnos"
DIST_DIR="${ROOT}/dist"
CACHE_DIR="${DIST_DIR}/cache"
ARCH="all"
VERSION="${VERSION:-}"
UPSTREAM_REPO="${UPSTREAM_REPO:-aimod-cc/Agent2API}"
PACKAGING_REPO="${PACKAGING_REPO:-https://github.com/caiyy/Agent2API_FnOS}"
WORK_DIRS=()

cleanup() {
    local directory
    if [ "${#WORK_DIRS[@]}" -eq 0 ]; then
        return
    fi
    for directory in "${WORK_DIRS[@]}"; do
        rm -rf "${directory}"
    done
}
trap cleanup EXIT

usage() {
    printf '%s\n' \
        "Usage: $0 [--arch x86|arm|all] [--version <upstream-version>] [--cache-dir <path>]" \
        "" \
        "Defaults:" \
        "  --arch all" \
        "  --version from UPSTREAM_VERSION" \
        "  --cache-dir dist/cache"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH="${2:-}"
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --cache-dir)
            CACHE_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "${ARCH}" in
    all|x86|arm) ;;
    *)
        printf 'Invalid architecture: %s (expected x86, arm, or all)\n' "${ARCH}" >&2
        exit 1
        ;;
esac

if [ -z "${VERSION}" ]; then
    if [ -f "${ROOT}/UPSTREAM_VERSION" ]; then
        VERSION="$(tr -d '[:space:]' < "${ROOT}/UPSTREAM_VERSION")"
    elif [ -f "${ROOT}/package.json" ]; then
        VERSION="$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)".*/\1/p' "${ROOT}/package.json" | head -1)"
    fi
fi
if [ -z "${VERSION}" ]; then
    printf 'Unable to determine version; pass --version\n' >&2
    exit 1
fi
case "${VERSION}" in
    ''|*[!0-9A-Za-z.+-]*)
        printf 'Invalid version: %s\n' "${VERSION}" >&2
        exit 1
        ;;
esac

for command in curl tar; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "${command}" >&2
        exit 1
    fi
done

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

md5_file() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | awk '{print $1}'
    else
        md5 -q "$1"
    fi
}

file_size() {
    if stat -f%z "$1" >/dev/null 2>&1; then
        stat -f%z "$1"
    else
        stat -c%s "$1"
    fi
}

download_release() {
    local asset="$1"
    local destination="${CACHE_DIR}/${asset}"
    local checksum_file="${destination}.sha256"
    local url="https://github.com/${UPSTREAM_REPO}/releases/download/v${VERSION}/${asset}"

    if [ -f "${destination}" ] && [ -f "${checksum_file}" ]; then
        local expected actual
        expected="$(awk '{print $1}' "${checksum_file}")"
        actual="$(sha256_file "${destination}")"
        if [ "${expected}" = "${actual}" ]; then
            printf 'Using cached %s\n' "${asset}"
            return
        fi
        rm -f "${destination}" "${checksum_file}"
    fi

    mkdir -p "${CACHE_DIR}"
    printf 'Downloading %s\n' "${url}"
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors \
        --connect-timeout 30 -o "${destination}.part" "${url}"
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors \
        --connect-timeout 30 -o "${checksum_file}.part" "${url}.sha256"

    local expected actual
    expected="$(awk '{print $1}' "${checksum_file}.part")"
    actual="$(sha256_file "${destination}.part")"
    if [ -z "${expected}" ] || [ "${expected}" != "${actual}" ]; then
        rm -f "${destination}.part" "${checksum_file}.part"
        printf 'SHA-256 verification failed for %s\n' "${asset}" >&2
        exit 1
    fi
    mv "${destination}.part" "${destination}"
    mv "${checksum_file}.part" "${checksum_file}"
}

build_one() {
    local platform="$1"
    local release_arch
    case "${platform}" in
        x86) release_arch="amd64" ;;
        arm) release_arch="arm64" ;;
    esac

    local asset="agent2api-server-linux-${release_arch}.tar.gz"
    local archive="${CACHE_DIR}/${asset}"
    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/agent2api-fnos.XXXXXX")"
    WORK_DIRS+=("${work}")

    download_release "${asset}"
    mkdir -p "${work}/upstream" "${work}/app" "${work}/package"
    tar -xzf "${archive}" -C "${work}/upstream"

    [ -x "${work}/upstream/agent2api-server" ] || {
        printf 'Upstream archive has no executable agent2api-server\n' >&2
        exit 1
    }
    [ -d "${work}/upstream/ui" ] || {
        printf 'Upstream archive has no ui directory\n' >&2
        exit 1
    }

    mkdir -p "${work}/app/bin" "${work}/app/config"
    cp -p "${work}/upstream/agent2api-server" "${work}/app/bin/agent2api-server"
    cp -a "${work}/upstream/ui" "${work}/app/ui"
    cp -p "${ROOT}/LICENSE" "${work}/app/LICENSE"
    cp -a "${ROOT}/licenses" "${work}/app/licenses"
    cp -p "${PACKAGE_DIR}/app-config/agent2api.env.example" \
        "${work}/app/config/agent2api.env.example"
    mkdir -p "${work}/app/packaging-fnos"
    cp -a "${PACKAGE_DIR}/." "${work}/app/packaging-fnos/"

    cat > "${work}/app/SOURCE.txt" <<EOF
Agent2API server binary and web UI are unmodified upstream artifacts.

Version: ${VERSION}
Release: https://github.com/${UPSTREAM_REPO}/releases/tag/v${VERSION}
Source:  https://github.com/${UPSTREAM_REPO}/tree/v${VERSION}
License: GNU Affero General Public License v3.0 (see LICENSE)

Upstream archive: ${asset}
Upstream SHA-256: $(sha256_file "${archive}")

fnOS packaging source is included under packaging-fnos.
Packaging repository: ${PACKAGING_REPO}
EOF

    (
        cd "${work}/app"
        tar -czf "${work}/app.tgz" .
    )

    local checksum
    checksum="$(md5_file "${work}/app.tgz")"

    cp -p "${work}/app.tgz" "${work}/package/app.tgz"
    cp -a "${PACKAGE_DIR}/cmd" "${work}/package/cmd"
    cp -a "${PACKAGE_DIR}/config" "${work}/package/config"
    cp -a "${PACKAGE_DIR}/ui" "${work}/package/ui"
    cp -p "${PACKAGE_DIR}/Agent2API.sc" "${work}/package/Agent2API.sc"
    cp -p "${PACKAGE_DIR}/health.json" "${work}/package/health.json"
    cp -p "${PACKAGE_DIR}/ICON.PNG" "${work}/package/ICON.PNG"
    cp -p "${PACKAGE_DIR}/ICON_256.PNG" "${work}/package/ICON_256.PNG"
    cp -p "${PACKAGE_DIR}/ICON_256.PNG" "${work}/package/ui/images/256.png"

    sed \
        -e "s|__VERSION__|${VERSION}|g" \
        -e "s|__PLATFORM__|${platform}|g" \
        -e "s|__CHECKSUM__|${checksum}|g" \
        "${PACKAGE_DIR}/manifest" > "${work}/package/manifest"

    chmod 0755 "${work}/package/cmd/"*
    mkdir -p "${DIST_DIR}"
    local output="${DIST_DIR}/agent2api_${VERSION}_${platform}.fpk"
    (
        cd "${work}/package"
        tar -czf "${output}" \
            manifest app.tgz cmd config ui Agent2API.sc health.json ICON.PNG ICON_256.PNG
    )

    if [ "$(file_size "${output}")" -lt 10000000 ]; then
        printf 'Generated package is unexpectedly small: %s\n' "${output}" >&2
        exit 1
    fi
    printf 'Built %s (%s bytes)\n' "${output}" "$(file_size "${output}")"
    rm -rf "${work}"
}

case "${ARCH}" in
    all)
        build_one x86
        build_one arm
        ;;
    *)
        build_one "${ARCH}"
        ;;
esac
