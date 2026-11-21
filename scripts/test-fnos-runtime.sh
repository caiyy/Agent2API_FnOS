#!/bin/bash
set -euo pipefail

FPK="${1:-}"
if [ -z "${FPK}" ] || [ ! -f "${FPK}" ]; then
    printf 'Usage: %s <package.fpk>\n' "$0" >&2
    exit 1
fi

for command in docker tar curl jq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "${command}" >&2
        exit 1
    fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent2api-fnos-runtime.XXXXXX")"
NAME="agent2api-fnos-runtime-$$-${RANDOM}"
cleanup() {
    docker stop "${NAME}" >/dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

mkdir -p "${WORK}/package" "${WORK}/app" "${WORK}/data"
tar -xzf "${FPK}" -C "${WORK}/package"
tar -xzf "${WORK}/package/app.tgz" -C "${WORK}/app"

manifest_value() {
    local key="$1"
    awk -F= -v key="${key}" '
        $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            sub(/^[[:space:]]+/, "", $2)
            sub(/[[:space:]]+$/, "", $2)
            print $2
            exit
        }
    ' "${WORK}/package/manifest"
}

platform="$(manifest_value platform)"
case "${platform}" in
    x86) docker_platform="linux/amd64" ;;
    arm) docker_platform="linux/arm64" ;;
    *)
        printf 'Unsupported package platform: %s\n' "${platform}" >&2
        exit 1
        ;;
esac

docker run -d --rm --name "${NAME}" --platform "${docker_platform}" \
    -p 127.0.0.1::3065 \
    -v "${WORK}/app:/app:ro" \
    -v "${WORK}/package/cmd:/pkgcmd:ro" \
    -v "${WORK}/data:/vol1/@appdata/agent2api" \
    debian:bookworm-slim sleep 900 >/dev/null

ENV_ARGS=(
    -e TRIM_APPDEST=/app
    -e TRIM_PKGVAR=/vol1/@appdata/agent2api
    -e TRIM_APPNAME=agent2api
    -e TRIM_SERVICE_PORT=3065
)

run_command() {
    docker exec "${ENV_ARGS[@]}" "${NAME}" "$@"
}

port_mapping="$(docker port "${NAME}" 3065/tcp | sed -n '1p')"
HOST_PORT="${port_mapping##*:}"
if ! [[ "${HOST_PORT}" =~ ^[0-9]+$ ]]; then
    printf 'Unable to determine mapped port: %s\n' "${port_mapping}" >&2
    exit 1
fi

wait_for_health() {
    local label="$1"
    local attempt
    for attempt in $(seq 1 45); do
        if curl -fsS --max-time 2 "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1; then
            return 0
        fi
        if ! docker inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null | grep -q true; then
            printf 'Container exited during %s\n' "${label}" >&2
            return 1
        fi
        sleep 1
    done
    printf 'Health check timed out during %s\n' "${label}" >&2
    return 1
}

run_command /pkgcmd/install_init
run_command /pkgcmd/install_callback
printf 'upgrade-marker\n' > "${WORK}/data/upgrade-marker"
printf '' > "${WORK}/data/agent2api.pid"
if run_command /pkgcmd/main status >/dev/null 2>&1; then
    printf 'Empty PID file was treated as a running service\n' >&2
    exit 1
fi

run_command /pkgcmd/main start
wait_for_health "first start"
run_command /pkgcmd/main status
run_command /pkgcmd/main stop

run_command /pkgcmd/upgrade_init
run_command /pkgcmd/upgrade_callback
[ -f "${WORK}/data/upgrade-marker" ] || {
    printf 'Upgrade removed persistent user data\n' >&2
    exit 1
}

run_command /pkgcmd/main start
wait_for_health "post-upgrade start"
run_command /pkgcmd/main status
run_command /pkgcmd/uninstall_init
run_command /pkgcmd/uninstall_callback

if curl -fsS --max-time 2 "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1; then
    printf 'Service is still reachable after uninstall\n' >&2
    exit 1
fi
[ -f "${WORK}/data/upgrade-marker" ] || {
    printf 'Uninstall removed retained user data\n' >&2
    exit 1
}

printf 'OK: runtime install/start/upgrade/uninstall cycle passed for %s\n' "${platform}"
