# Trove's PostgreSQL backup image for amd64 and ppc64le. Upstream's backup/Dockerfile and
# install.sh build it on Ubuntu with an amd64-only PostgreSQL repository line and an amd64
# dumb-init download, so this recipe takes the same steps on Debian trixie: the PostgreSQL
# project's client for the major Trove asks for, Debian's dumb-init, and Trove's backup/
# directory (the build context) in the venv upstream builds, with upstream's requirements.
# Those are installed with kolla's upper-constraints (the build context "constraints"), as
# kolla's images and the guest agent are, so both architectures hold the same versions and
# ppc64le takes the compiled wheels PyPI lacks from this repository's index.
FROM debian:trixie-slim

ARG PG_MAJOR
ARG TARGETARCH
ARG APTOPTS="-y -qq --no-install-recommends"

RUN test -n "$PG_MAJOR" \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install $APTOPTS ca-certificates curl netbase dumb-init python3 python3-venv \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && printf '%s\n' 'Types: deb' 'URIs: https://apt.postgresql.org/pub/repos/apt' 'Suites: trixie-pgdg' 'Components: main' \
        'Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc' > /etc/apt/sources.list.d/pgdg.sources \
    && apt-get update \
    && apt-get install $APTOPTS "postgresql-client-$PG_MAJOR" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/trove/backup
COPY --from=constraints upper-constraints.txt /opt/upper-constraints.txt
WORKDIR /opt/trove/backup

RUN if [ "$TARGETARCH" = ppc64le ]; then export PIP_EXTRA_INDEX_URL=https://77997.github.io/images-ppc64le/simple/; fi \
    && python3 -m venv /opt/trove-backup-venv \
    && /opt/trove-backup-venv/bin/pip3 --no-cache-dir install -U -c /opt/upper-constraints.txt -r requirements.txt

ENV PATH=/opt/trove-backup-venv/bin:$PATH

ENTRYPOINT ["dumb-init", "--single-child", "--"]
