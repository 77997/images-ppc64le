FROM docker.io/library/debian:trixie

ARG GERRIT_VERSION
ARG GERRIT_MD5

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-25-jre-headless git openssh-client curl ca-certificates procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -u 1000 -m -d /var/gerrit gerrit \
 && mkdir -p /var/gerrit/bin \
 && curl -fsSLo /var/gerrit/bin/gerrit.war "https://gerrit-releases.storage.googleapis.com/gerrit-${GERRIT_VERSION}.war" \
 && echo "${GERRIT_MD5}  /var/gerrit/bin/gerrit.war" | md5sum -c - \
 && chown -R gerrit:gerrit /var/gerrit

COPY entrypoint.sh /entrypoint.sh

USER gerrit
WORKDIR /var/gerrit
EXPOSE 8080 29418
ENTRYPOINT ["/entrypoint.sh"]
