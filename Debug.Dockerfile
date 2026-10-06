ARG DEBIAN_BASE_IMAGE=python:3.14.8-slim-trixie@sha256:f85c5697265c178cc6887276c55fe16cf3d14ca35c3df6a5eab3b360534a55d2
ARG DISTROLESS_DEBUG_IMAGE=gcr.io/distroless/base-debian13:debug-nonroot-5d2a01416bd6e31ecc4c834eb03fc8d3b711a072@sha256:dac9324d89e38f9b5b92c59437ff9ac79f6e2e3eaaba6b0a55c0a80522e02c11

# Stage 1: Build the application in a Debian-based image (identical to the production build)
FROM ${DEBIAN_BASE_IMAGE} AS builder
ARG POWERDNS_API_PROXY_VERSION
RUN test -n "${POWERDNS_API_PROXY_VERSION}" || { echo "POWERDNS_API_PROXY_VERSION build-arg is required"; exit 1; }

RUN pip install --upgrade pip
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    tar

RUN /usr/local/bin/python3 -m pip install --upgrade https://github.com/akquinet/powerdns-api-proxy/archive/refs/tags/${POWERDNS_API_PROXY_VERSION}.tar.gz

# We do not use venv, since distroless does not include the most current python version.
# Instead we copy the full python installation (interpreter, stdlib, site-packages and the
# shared libpython it depends on) preserving the original /usr/local prefix layout, so
# Python's own path-finding logic (relative to the executable) keeps working unmodified.
RUN PYTHON_VERSION=$(python3 --version | sed -E 's/(Python\s+|\.[0-9]+$)//g') && \
    mkdir -p \
        /runtime/usr/local/bin \
        /runtime/usr/local/lib \
    && cp -a /usr/local/bin/python${PYTHON_VERSION} /runtime/usr/local/bin/python${PYTHON_VERSION} \
    && ln -s python${PYTHON_VERSION} /runtime/usr/local/bin/python3 \
    && cp -a /usr/local/lib/python${PYTHON_VERSION} /runtime/usr/local/lib/python${PYTHON_VERSION} \
    && cp -a /usr/local/lib/libpython${PYTHON_VERSION}.so* /runtime/usr/local/lib/

# Find and copy all shared libraries required by the interpreter that are not
# already provided by the distroless base image. This must include not only the
# interpreter binary itself, but also every compiled C extension (*.so) shipped by
# installed packages, since those bring their own shared library dependencies
# that distroless does not include.
RUN PYTHON_VERSION=$(python3 --version | sed -E 's/(Python\s+|\.[0-9]+$)//g') && \
    mkdir -p /runtime/usr/lib/aarch64-linux-gnu && \
    { \
      ldd /usr/local/bin/python${PYTHON_VERSION}; \
      find /usr/local/lib/python${PYTHON_VERSION}/site-packages -name '*.so*' -exec ldd {} \; 2>/dev/null; \
    } \
        | awk '/=>/ {print $3} !/=>/ {if ($1 ~ /^\//) print $1}' \
        | sort -u \
        | xargs -I '{}' readlink -f '{}' \
        | sort -u \
        | xargs -I '{}' cp -av --parents '{}' /runtime/ || true

RUN chown -R 65532:65532 /runtime

# Stage 2: distroless debug image (includes a busybox shell) for interactive troubleshooting.
# powerdns-api-proxy is NOT started automatically; exec into the container to run it manually.
FROM ${DISTROLESS_DEBUG_IMAGE} AS final
ARG POWERDNS_API_PROXY_VERSION

LABEL \
    org.opencontainers.image.authors="Joern Schonhoff" \
    org.opencontainers.image.description="powerdns-api-proxy ${POWERDNS_API_PROXY_VERSION} Debug based on distroless debug-nonroot (busybox shell)" \
    org.opencontainers.image.licenses="GPL-3.0-only" \
    org.opencontainers.image.source="https://gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless" \
    org.opencontainers.image.title="powerdns-api-proxy-distroless-debug" \
    org.opencontainers.image.url="https://gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless" \
    org.opencontainers.image.version="${POWERDNS_API_PROXY_VERSION}"
    #   org.opencontainers.image.created="FILLED BY BUILD SYSTEM"
    #   org.opencontainers.image.revision="FILLED BY BUILD SYSTEM"

COPY --from=builder /runtime/ /

EXPOSE 8000/tcp

# debug-nonroot already runs as UID/GID 65532 by default; set explicitly for clarity.
USER 65532:65532

ENTRYPOINT [ "/busybox/sh" ]
CMD [ "-c", "while true; do sleep 100; done" ]
