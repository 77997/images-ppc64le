FROM docker.io/library/debian:trixie

ARG GERRIT_VERSION
ARG GERRIT_MD5

# The site is a volume mounted at /var/gerrit, so the war and the OAuth plugin live outside it: a site whose
# gerrit.config sets container.war = /opt/gerrit/gerrit.war runs the image's own war, and a new image upgrades it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-25-jre-headless git openssh-client curl ca-certificates procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -u 1000 -M -d /var/gerrit -s /bin/bash gerrit \
 && install -d -o gerrit -g gerrit /var/gerrit \
 && install -d /opt/gerrit /opt/gerrit-plugins \
 && curl -fsSLo /opt/gerrit/gerrit.war "https://gerrit-releases.storage.googleapis.com/gerrit-${GERRIT_VERSION}.war" \
 && echo "${GERRIT_MD5}  /opt/gerrit/gerrit.war" | md5sum -c - \
 && chmod 644 /opt/gerrit/gerrit.war

# Built by build-oauth-plugin.sh before the image; it is copied into the site's plugins when the site is prepared.
COPY --chmod=644 oauth.jar /opt/gerrit-plugins/oauth.jar
COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER gerrit
WORKDIR /var/gerrit
EXPOSE 8080 29418
ENTRYPOINT ["/entrypoint.sh"]
