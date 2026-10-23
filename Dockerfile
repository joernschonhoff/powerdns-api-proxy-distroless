ARG DEBIAN_BASE_IMAGE=python:3.15.1-slim-trixie@sha256:08275f764e022331c6d3e3ca55d8cce01fa4684b02111adf0445d71806fe7941
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian13:nonroot-5d2a01416bd6e31ecc4c834eb03fc8d3b711a072@sha256:a0d70d6a97cd697d9362bc2aae4a6560dd65817e365d0043b07325a97975dc91

# Stage 1: Build the application in a Debian-based image
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

# Stage 2: Create the final distroless image
FROM ${DISTROLESS_IMAGE} AS final

# Re-declare build arg needed in this stage (ARGs before FROM are scoped to the FROM they precede)
ARG POWERDNS_API_PROXY_VERSION

# SPDX identifier required by the OCI image-spec for org.opencontainers.image.licenses
LABEL \
    org.opencontainers.image.authors="Joern Schonhoff" \
    org.opencontainers.image.description="powerdns-api-proxy ${POWERDNS_API_PROXY_VERSION} distroless" \
    org.opencontainers.image.licenses="GPL-3.0-only" \
    org.opencontainers.image.source="https://gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless" \
    org.opencontainers.image.title="powerdns-api-proxy-distroless" \
    org.opencontainers.image.url="https://gitlab.com/joern_schonhoff/powerdns-api-proxy-distroless" \
    org.opencontainers.image.version="${POWERDNS_API_PROXY_VERSION}"
    #   org.opencontainers.image.created="FILLED BY BUILD SYSTEM"
    #   org.opencontainers.image.revision="FILLED BY BUILD SYSTEM"

COPY --from=builder /runtime/ /

EXPOSE 8000/tcp

USER 65532:65532
ENTRYPOINT [ "/usr/local/bin/python3", "-m", "powerdns_api_proxy" ]
