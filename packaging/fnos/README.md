# Agent2API for fnOS

This directory contains a native fnOS package definition for Agent2API. The
package runs the official Linux server binary as an unprivileged application
user, stores state in the fnOS application data directory, and opens the
upstream web panel from the fnOS desktop.

## Build

From the repository root:

```bash
./scripts/build-fnos.sh --arch all
```

The script downloads the matching official server archive and SHA-256 file
from the upstream GitHub Release, verifies both, and writes:

```text
dist/agent2api_<version>_x86.fpk
dist/agent2api_<version>_arm.fpk
```

Use `--version <version>` to package a different upstream release. Use
`--arch x86` or `--arch arm` to build only one architecture.

## Runtime layout

- Program files: `TRIM_APPDEST`
- Persistent state: `TRIM_PKGVAR`
- Editable environment file: `TRIM_PKGVAR/agent2api.env`
- Service log: `TRIM_PKGVAR/logs/server.log`
- Panel and API: port `3065` by default

The package deliberately disables Agent2API's container/systemd self-update
paths. Upgrades are performed by installing a newer `.fpk` through fnOS
Application Center.

## Verification

```bash
./scripts/verify-fnos.sh dist/agent2api_<version>_x86.fpk
./scripts/verify-fnos.sh dist/agent2api_<version>_arm.fpk
```

The checker validates the FPK structure, manifest checksum, payload contents,
shell syntax, and ELF architecture. A live install test should be repeated on
a real fnOS device before publishing a package.

With Docker available, the repository can also exercise the fnOS lifecycle in
an isolated Debian container:

```bash
./scripts/test-fnos-runtime.sh dist/agent2api_<version>_x86.fpk
./scripts/test-fnos-runtime.sh dist/agent2api_<version>_arm.fpk
```

This runs install, start, health probe, stop, upgrade with data retention,
restart, uninstall, and retained-data checks using fnOS-style `TRIM_*` paths.
