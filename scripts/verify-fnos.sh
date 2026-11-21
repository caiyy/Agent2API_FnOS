#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FPK="${1:-}"

if [ -z "${FPK}" ] || [ ! -f "${FPK}" ]; then
    printf 'Usage: %s <package.fpk>\n' "$0" >&2
    exit 1
fi

for command in tar file jq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "${command}" >&2
        exit 1
    fi
done

manifest_get() {
    local key="$1"
    awk -F= -v key="${key}" '
        $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            sub(/^[[:space:]]+/, "", $2)
            sub(/[[:space:]]+$/, "", $2)
            print $2
            exit
        }
    ' "${WORK}/manifest"
}

md5_file() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | awk '{print $1}'
    else
        md5 -q "$1"
    fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent2api-verify.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

file -b "${FPK}" | grep -q 'gzip' || {
    printf 'FAIL: package is not a gzip archive\n' >&2
    exit 1
}
tar -xzf "${FPK}" -C "${WORK}"

for entry in manifest app.tgz cmd/main cmd/common cmd/installer \
    cmd/install_init cmd/install_callback cmd/uninstall_init \
    cmd/uninstall_callback cmd/upgrade_init cmd/upgrade_callback \
    config/privilege config/resource ui/config ICON.PNG ICON_256.PNG \
    Agent2API.sc health.json; do
    [ -e "${WORK}/${entry}" ] || {
        printf 'FAIL: missing %s\n' "${entry}" >&2
        exit 1
    }
done

appname="$(manifest_get appname)"
version="$(manifest_get version)"
platform="$(manifest_get platform)"
port="$(manifest_get service_port)"
checksum="$(manifest_get checksum)"

case "${appname}" in
    agent2api) ;;
    *) printf 'FAIL: invalid appname %s\n' "${appname}" >&2; exit 1 ;;
esac
case "${version}" in
    ''|*[!0-9A-Za-z.+-]*) printf 'FAIL: invalid version %s\n' "${version}" >&2; exit 1 ;;
esac
case "${platform}" in
    x86|arm) ;;
    *) printf 'FAIL: invalid platform %s\n' "${platform}" >&2; exit 1 ;;
esac
[ "${port}" = "3065" ] || {
    printf 'FAIL: unexpected service_port %s\n' "${port}" >&2
    exit 1
}
[ "${checksum}" = "$(md5_file "${WORK}/app.tgz")" ] || {
    printf 'FAIL: app.tgz checksum mismatch\n' >&2
    exit 1
}

jq -e '.defaults["run-as"] == "package"' "${WORK}/config/privilege" >/dev/null
jq -e '.["port-config"]["protocol-file"] == "Agent2API.sc"' "${WORK}/config/resource" >/dev/null
jq -e '.[".url"]["agent2api.Application"].port == "3065"' "${WORK}/ui/config" >/dev/null
jq -e '.path == "/health" and .type == "http"' "${WORK}/health.json" >/dev/null

for script in "${WORK}"/cmd/*; do
    case "${script}" in
        *common|*installer|*service-setup|*.sh|*/*)
            ;;
    esac
    case "$(basename "${script}")" in
        *.md) continue ;;
    esac
    bash -n "${script}" || {
        printf 'FAIL: shell syntax error in %s\n' "${script}" >&2
        exit 1
    }
done

mkdir -p "${WORK}/app"
tar -xzf "${WORK}/app.tgz" -C "${WORK}/app"
[ -x "${WORK}/app/bin/agent2api-server" ] || {
    printf 'FAIL: missing executable payload\n' >&2
    exit 1
}
[ -f "${WORK}/app/ui/index.html" ] || {
    printf 'FAIL: missing web panel\n' >&2
    exit 1
}
[ -f "${WORK}/app/config/agent2api.env.example" ] || {
    printf 'FAIL: missing configuration example\n' >&2
    exit 1
}
[ -f "${WORK}/app/LICENSE" ] || {
    printf 'FAIL: missing upstream license\n' >&2
    exit 1
}
[ -f "${WORK}/app/ui/config" ] || {
    printf 'FAIL: app.tgz is missing ui/config\n' >&2
    exit 1
}
[ -f "${WORK}/app/ui/images/icon_64.png" ] || {
    printf 'FAIL: app.tgz is missing ui/images/icon_64.png\n' >&2
    exit 1
}
[ -f "${WORK}/app/ui/images/icon_256.png" ] || {
    printf 'FAIL: app.tgz is missing ui/images/icon_256.png\n' >&2
    exit 1
}
jq -e '.[".url"]["agent2api.Application"].icon == "images/icon_{0}.png"' \
    "${WORK}/app/ui/config" >/dev/null || {
    printf 'FAIL: app/ui/config uses the wrong icon template\n' >&2
    exit 1
}
file -b "${WORK}/app/ui/images/icon_64.png" | grep -q '64 x 64' || {
    printf 'FAIL: app/ui/images/icon_64.png is not 64x64\n' >&2
    exit 1
}
file -b "${WORK}/app/ui/images/icon_256.png" | grep -q '256 x 256' || {
    printf 'FAIL: app/ui/images/icon_256.png is not 256x256\n' >&2
    exit 1
}
file -b "${WORK}/ICON.PNG" | grep -q '64 x 64' || {
    printf 'FAIL: ICON.PNG is not 64x64\n' >&2
    exit 1
}

binary_description="$(file -b "${WORK}/app/bin/agent2api-server")"
case "${platform}" in
    x86) expected="x86-64" ;;
    arm) expected="aarch64" ;;
esac
printf '%s\n' "${binary_description}" | grep -q 'ELF' || {
    printf 'FAIL: payload is not an ELF binary\n' >&2
    exit 1
}
printf '%s\n' "${binary_description}" | grep -q "${expected}" || {
    printf 'FAIL: binary architecture mismatch: %s\n' "${binary_description}" >&2
    exit 1
}

printf 'OK: %s\n' "$(basename "${FPK}")"
printf '  app=%s version=%s platform=%s port=%s\n' "${appname}" "${version}" "${platform}" "${port}"
printf '  binary=%s\n' "${binary_description}"
