# powerdns-api-proxy-distroless

A distroless container image for [powerdns-api-proxy](https://github.com/akquinet/powerdns-api-proxy), an API proxy for PowerDNS implementing multiple tokens and fine-grained access control.

## Purpose & Warning

This is a **hobby / learning project**. It is **not intended for production use** — it lacks typical hardening, monitoring, and operational features you would expect from a production-grade deployment. Use at your own risk.

This project is **not affiliated with, endorsed by, or associated with akquinet AG or PowerDNS.com B.V.** in any form. "PowerDNS" is a trademark of PowerDNS.com B.V.; this image simply installs and packages the official, publicly available `powerdns-api-proxy` source releases.

## Contents

- Minimal Docker build for `powerdns-api-proxy`
  - Built from the official GitHub release tarball (`POWERDNS_API_PROXY_VERSION` build-arg, pinned via the `VERSION` file)
  - Compiled in a `python:3.14-slim-trixie` builder stage, since distroless images don't ship a package manager to install Python packages directly
  - The full Python installation (interpreter, stdlib, site-packages, and `libpython`) is copied into the final image, preserving the `/usr/local` layout so Python's own path-finding logic keeps working unmodified
  - All shared library dependencies of the interpreter and any compiled C extensions (`*.so` files from installed packages) are detected via `ldd` and copied in as well
- Final runtime image is based on `gcr.io/distroless/base-debian13:nonroot` — no shell, no package manager
- Runs as a non-root user (UID/GID 65532)
- `Debug.Dockerfile` variant available for interactive troubleshooting
  - Same multi-stage build as the production image, but the final stage is based on `gcr.io/distroless/base-debian13:debug-nonroot`, which bundles a busybox shell (`/busybox/sh`) while still running as the non-root UID 65532

## Quickstart

### Build

The project ships a `Makefile` that wraps the `docker buildx` invocations (reads the version from `VERSION`, sets labels, tags, etc.):

```bash
# Show all available targets
make help

# Build production image
make build-prod

# Build debug image
make build-debug

# Build both
make build
```

### Running

`make build-prod` tags the image as `registry.gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless:<version>` (override with `CI_REGISTRY_IMAGE=<name> make build-prod` for a local-only tag).

```bash
docker run --rm \
  -v /path/to/config.yml:/config/config.yml:ro \
  -e PROXY_CONFIG_PATH=/config/config.yml \
  -e LOG_LEVEL=INFO \
  -e LOG_FORMAT=json \
  -p 8000:8000 \
  registry.gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless:$(cat VERSION)
```

Note: Runtime configuration (volumes, environment variables, networks) depends on your setup.

The debug image has no entrypoint that runs `powerdns-api-proxy` automatically — its `CMD` sleeps forever so you can `exec` into the container and start it manually:

```bash
docker exec <container-id> /busybox/sh -c "python3 -m powerdns_api_proxy"
```

## Examples

The `example/` directory contains a complete Docker Compose stack: `powerdns-api-proxy` fronting a `pdns-auth-distroless` (SQLite backend) instance.

```bash
cd example
docker compose up -d
```

This brings up PowerDNS Authoritative (listening on `5353/tcp+udp`) and `powerdns-api-proxy` (listening on `8000/tcp`), pre-configured with a single example token (`example_api_proxy_token_change_me`) that has admin rights on the `example.com` zone (see `example/config.yml`).

```bash
# Create the example.com zone through the proxy
curl -X POST http://localhost:8000/api/v1/servers/localhost/zones \
  -H "X-API-Key: example_api_proxy_token_change_me" \
  -H "Content-Type: application/json" \
  -d '{"name":"example.com.","kind":"Native","nameservers":["ns1.example.com."]}'
```

**Warning:** The example token/config is for local testing only — generate your own token hash (see [upstream docs](https://github.com/akquinet/powerdns-api-proxy#environment)) before using this anywhere reachable from an untrusted network.

## Configuration

`powerdns-api-proxy` is configured via a YAML file, pointed to with the `PROXY_CONFIG_PATH` environment variable. See the [upstream README](https://github.com/akquinet/powerdns-api-proxy#configuration) for the full configuration reference (environments, zones, records, RBAC, metrics, etc.).

Relevant environment variables:

```
PROXY_CONFIG_PATH=/config/config.yml  # Required: path to the YAML config file
LOG_LEVEL=INFO                        # Optional: DEBUG, INFO, WARNING, ERROR (default: DEBUG)
LOG_FORMAT=json                       # Optional: "text" (default) or "json" for structured logging
LOG_FILE=false                        # Optional: log file path (default: "log"), set to "false" to disable file logging
LISTEN_HOST=0.0.0.0                   # Optional: host to bind to (default: *)
LISTEN_PORT=8000                      # Optional: port to listen on (default: 8000)
AUDIT_LOGGING=true                    # Optional: disable automatic audit logging of API requests
```

## Version Management

The `powerdns-api-proxy` version is stored in the `VERSION` file. When a new version is released:

1. Update the `VERSION` file with the new version number
2. Build and test the image
3. Commit the change

**Automated Updates:** The project is configured for Renovate bot, which will:
- Monitor the [akquinet/powerdns-api-proxy GitHub releases](https://github.com/akquinet/powerdns-api-proxy/releases) for new versions
- Automatically create PRs when new versions are detected
- Extract the version number and update the `VERSION` file
- Auto-merge is enabled for minor/patch updates; major updates require manual review

## License

GPL-3.0 (GNU General Public License v3)

This project bundles `powerdns-api-proxy`, which is licensed under GPL-3.0. See the LICENSE file for the full text.
