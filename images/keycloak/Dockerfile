# syntax=docker/dockerfile:1
# Keycloak from its release distribution, built once for the PostgreSQL database with its health endpoints. The built
# server is Java alone, the same on every architecture, so it is built on the build platform, natively, and copied
# into a runtime stage for each target platform, which adds nothing but its own JRE.

FROM --platform=$BUILDPLATFORM docker.io/library/debian:trixie AS build

ARG KEYCLOAK_VERSION
ARG KEYCLOAK_URL
ARG KEYCLOAK_SHA256

# kc.sh build needs no compiler: Quarkus's augmentation runs on the headless JRE, the only Java Keycloak's own image
# carries.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jre-headless curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Every build argument comes from release.env; an empty one would download or check nothing, so the build stops.
RUN set -eu; \
    for name in KEYCLOAK_VERSION KEYCLOAK_URL KEYCLOAK_SHA256; do \
      eval "value=\${$name:-}"; \
      [ -n "$value" ] || { echo "Build argument $name is empty: pass every value release.env names" >&2; exit 1; }; \
    done

# The distribution unpacks into keycloak-<version>, so a directory of any other name is not the release asked for.
RUN set -eu; \
    curl -fsSLo /tmp/keycloak.tar.gz "$KEYCLOAK_URL"; \
    echo "$KEYCLOAK_SHA256  /tmp/keycloak.tar.gz" | sha256sum -c -; \
    install -d /tmp/keycloak; \
    tar -xzf /tmp/keycloak.tar.gz -C /tmp/keycloak --no-same-owner; \
    rm /tmp/keycloak.tar.gz; \
    [ -f "/tmp/keycloak/keycloak-$KEYCLOAK_VERSION/bin/kc.sh" ] \
      || { echo "The archive does not hold Keycloak $KEYCLOAK_VERSION" >&2; exit 1; }; \
    mv "/tmp/keycloak/keycloak-$KEYCLOAK_VERSION" /opt/keycloak; \
    rm -r /tmp/keycloak

# The build-time options sso-1 needs, and no others: db and health-enabled are each marked buildTime in Keycloak
# 26.8.2's DatabaseOptions and HealthOptions, while cache carries no such mark there, so the local cache is chosen at
# start. The build writes them into lib/quarkus/generated-bytecode.jar, where the server reads them back. What the
# build leaves in data is removed, so the image's one writable directory starts empty.
RUN /opt/keycloak/bin/kc.sh build --db=postgres --health-enabled=true \
 && rm -rf /opt/keycloak/data

FROM docker.io/library/debian:trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system -g 1000 keycloak \
 && useradd --system -u 1000 -g 1000 -M -d /opt/keycloak -s /usr/sbin/nologin keycloak

# The keycloak user owns only data, where the server keeps its temporary files while it runs. Everything else, the
# built server in lib/quarkus included, stays root's, so a start that changes a build-time option, which would rebuild
# the server in place, fails rather than running a server other than the one this image built; the server is
# started with start --optimized.
COPY --from=build /opt/keycloak /opt/keycloak
RUN install -d -o keycloak -g keycloak /opt/keycloak/data

# KC_RUN_IN_CONTAINER, as Keycloak's own image sets it, makes kc.sh size the heap at 70% of the container's memory
# limit rather than a fixed 512 MiB, and warns when the server is not the container's first process.
ENV KC_RUN_IN_CONTAINER=true

USER keycloak
WORKDIR /opt/keycloak
EXPOSE 8080 8443 9000
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
