# syntax=docker/dockerfile:1
# EJBCA CE built from Keyfactor's source and deployed on WildFly. The ear, the CLI and the configured WildFly tree are
# Java alone, so they are built once on the build platform, natively, and copied into a runtime stage for each target
# platform, which adds nothing but its own JRE.
# The image always starts against an existing EJBCA database: no install step runs and no CA is created, and EJBCA
# upgrades the schema itself when it deploys.

FROM --platform=$BUILDPLATFORM docker.io/library/debian:trixie AS build

ARG EJBCA_VERSION
ARG EJBCA_SOURCE_URL
ARG EJBCA_SOURCE_SHA256
ARG WILDFLY_VERSION
ARG WILDFLY_URL
ARG WILDFLY_SHA256
ARG POSTGRESQL_JDBC_URL
ARG POSTGRESQL_JDBC_SHA256

# Ant runs EJBCA's build; its build files hold no script task, so Ant needs no JavaScript engine on JDK 21.
# ant-optional carries the optional tasks some module build files declare.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk-headless ant ant-optional curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Every build argument comes from release.env; an empty one would download or check nothing, so the build stops.
RUN set -eu; \
    for name in EJBCA_VERSION EJBCA_SOURCE_URL EJBCA_SOURCE_SHA256 WILDFLY_VERSION WILDFLY_URL WILDFLY_SHA256 \
                POSTGRESQL_JDBC_URL POSTGRESQL_JDBC_SHA256; do \
      eval "value=\${$name:-}"; \
      [ -n "$value" ] || { echo "Build argument $name is empty: pass every value release.env names" >&2; exit 1; }; \
    done

# WildFly, unpacked where both EJBCA's build (which compiles the CLI against bin/client/jboss-client.jar) and the
# runtime expect it.
RUN set -eu; \
    curl -fsSLo /tmp/wildfly.tar.gz "$WILDFLY_URL"; \
    echo "$WILDFLY_SHA256  /tmp/wildfly.tar.gz" | sha256sum -c -; \
    install -d /opt/wildfly; \
    tar -xzf /tmp/wildfly.tar.gz -C /opt/wildfly --strip-components=1 --no-same-owner; \
    rm /tmp/wildfly.tar.gz; \
    [ -f "/opt/wildfly/jboss-modules.jar" ] && [ -f /opt/wildfly/bin/client/jboss-client.jar ] \
      || { echo "The WildFly $WILDFLY_VERSION archive does not hold the expected tree" >&2; exit 1; }

# The PostgreSQL JDBC driver as the module org.postgresql.
COPY org.postgresql.module.xml /opt/wildfly/modules/org/postgresql/main/module.xml
RUN set -eu; \
    curl -fsSLo /opt/wildfly/modules/org/postgresql/main/postgresql-jdbc.jar "$POSTGRESQL_JDBC_URL"; \
    echo "$POSTGRESQL_JDBC_SHA256  /opt/wildfly/modules/org/postgresql/main/postgresql-jdbc.jar" | sha256sum -c -

# RESTEasy's crypto module loads its own Bouncy Castle, which conflicts with the one EJBCA ships; Keyfactor removes it.
RUN set -eu; \
    module=/opt/wildfly/modules/system/layers/base/org/jboss/as/jaxrs/main/module.xml; \
    grep -q 'org.jboss.resteasy.resteasy-crypto' "$module"; \
    sed -i '/.*org.jboss.resteasy.resteasy-crypto.*/d' "$module"; \
    rm -r /opt/wildfly/modules/system/layers/base/org/jboss/resteasy/resteasy-crypto

# EJBCA's source, with the configuration of the EJBCA this image replaces and the ports its web listens on. The conf
# files are read by the build and carried inside the ear and the CLI.
RUN set -eu; \
    curl -fsSLo /tmp/ejbca.tar.gz "$EJBCA_SOURCE_URL"; \
    echo "$EJBCA_SOURCE_SHA256  /tmp/ejbca.tar.gz" | sha256sum -c -; \
    install -d /build/ejbca; \
    tar -xzf /tmp/ejbca.tar.gz -C /build/ejbca --strip-components=1 --no-same-owner; \
    rm /tmp/ejbca.tar.gz; \
    grep -qx "app.version.number=$EJBCA_VERSION" /build/ejbca/src/internal.properties \
      || { echo "The source archive is not EJBCA $EJBCA_VERSION" >&2; exit 1; }
COPY conf/cesecore.properties conf/database.properties conf/ejbca.properties conf/web.properties /build/ejbca/conf/

# build is Keyfactor's target for the ear (dist/ejbca.ear); ejbca-ejb-cli builds dist/ejbca-ejb-cli, which
# bin/ejbca.sh runs. APPSRV_HOME tells the build which application server it targets.
WORKDIR /build/ejbca
RUN APPSRV_HOME=/opt/wildfly ant build ejbca-ejb-cli \
 && [ -f dist/ejbca.ear ] && [ -f dist/ejbca-ejb-cli/ejbca-ejb-cli.jar ] \
 && install -d /opt/ejbca/bin /opt/ejbca/dist \
 && cp bin/ejbca.sh bin/log4j-cli.properties /opt/ejbca/bin/ \
 && cp -r dist/ejbca-ejb-cli /opt/ejbca/dist/

# WildFly's configuration, written by jboss-cli against an embedded server, so no server runs during the build.
# Elytron starts its key stores even in admin-only mode, because the management interface depends on it, so the
# embedded server resolves the ${env.*} expressions and opens the TLS stores while the batch runs. It is given
# throwaway values and a throwaway self-signed store at the runtime paths for this step alone; jboss-cli sends the
# expressions unresolved, so standalone.xml keeps them, which the check below proves before the throwaway store goes.
# The admin-only server leaves logging.properties, the boot logger's configuration, as WildFly ships it, with a
# FILE handler writing server.log; it is edited to the console alone, as the logging subsystem already is.
# What the embedded server leaves behind (its history, data, logs and temporary files) is removed, so the image's
# writable directories start empty. The ear goes into the deployments directory only afterwards, so the embedded
# server never sees it.
COPY configure-wildfly.cli /build/configure-wildfly.cli
RUN install -d -m 0700 /etc/ejbca/tls \
 && keytool -genkeypair -noprompt -alias build -keyalg EC -groupname secp256r1 -dname CN=build -validity 1 \
      -storetype PKCS12 -keystore /etc/ejbca/tls/keystore.p12 -storepass build-only -keypass build-only \
 && cp /etc/ejbca/tls/keystore.p12 /etc/ejbca/tls/truststore.p12 \
 && EJBCA_DATABASE_URL=jdbc:postgresql://localhost/build EJBCA_DATABASE_USER=build EJBCA_DATABASE_PASSWORD=build-only \
    EJBCA_KEYSTORE_PASSWORD=build-only EJBCA_TRUSTSTORE_PASSWORD=build-only \
    /opt/wildfly/bin/jboss-cli.sh --file=/build/configure-wildfly.cli \
 && rm -rf /etc/ejbca \
 && for name in EJBCA_DATABASE_URL EJBCA_DATABASE_USER EJBCA_DATABASE_PASSWORD EJBCA_KEYSTORE_PASSWORD \
                EJBCA_TRUSTSTORE_PASSWORD; do \
      grep -q "\${env.$name}" /opt/wildfly/standalone/configuration/standalone.xml \
        || { echo "standalone.xml does not hold the expression for $name" >&2; exit 1; }; \
    done \
 && if grep -Eq 'build-only|jdbc:postgresql://localhost/build' /opt/wildfly/standalone/configuration/standalone.xml; then \
      echo "standalone.xml holds a build-only value in place of an expression" >&2; exit 1; \
    fi \
 && sed -i -e 's/^logger\.handlers=.*/logger.handlers=CONSOLE/' -e '/^handler\.FILE/d' -e '/^formatter\.PATTERN/d' \
      /opt/wildfly/standalone/configuration/logging.properties \
 && rm -rf /opt/wildfly/standalone/configuration/standalone_xml_history \
           /opt/wildfly/standalone/data /opt/wildfly/standalone/log /opt/wildfly/standalone/tmp \
           /opt/wildfly/welcome-content \
 && if grep -Eq '^logger\.handlers=(.*,)?FILE(,|$)' /opt/wildfly/standalone/configuration/logging.properties; then \
      echo "logging.properties still names the FILE handler, so every start's boot logger would write server.log" >&2; \
      exit 1; \
    fi \
 && cp /build/ejbca/dist/ejbca.ear /opt/wildfly/standalone/deployments/ejbca.ear

FROM docker.io/library/debian:trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -g 1000 ejbca \
 && useradd -u 1000 -g 1000 -M -d /opt/wildfly -s /usr/sbin/nologin ejbca

COPY --from=build /opt/wildfly /opt/wildfly
COPY --from=build /opt/ejbca /opt/ejbca
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# The ejbca user owns only what WildFly writes while it runs: its configuration directory (where it keeps the
# history of standalone.xml), data, logs, temporary files and the deployment scanner's marker files beside the ear.
# Everything else, the ear and the configured standalone.xml's tree included, stays root's.
RUN set -eu; \
    install -d -o ejbca -g ejbca /opt/wildfly/standalone/data /opt/wildfly/standalone/log /opt/wildfly/standalone/tmp; \
    chown ejbca:ejbca /opt/wildfly/standalone/deployments; \
    chown -R ejbca:ejbca /opt/wildfly/standalone/configuration; \
    chmod 644 /opt/wildfly/standalone/deployments/ejbca.ear

# EJBCA_JAVA_OPTS becomes the server's JAVA_OPTS in the entrypoint alone, replacing WildFly's defaults, which would
# prefer IPv4. It is not JAVA_OPTS itself because jboss-cli.sh passes JAVA_OPTS to its own JVM, so a CLI session
# opened with docker exec would take a second 2 GiB heap inside the same 3 GiB limit.
# - The heap is fixed at 2 GiB, Keyfactor's minimum, and AlwaysPreTouch touches every page of it at start, so the
#   cgroup is charged for it then and a limit it cannot fit in fails at start rather than under load. Metaspace, code
#   cache and direct memory are capped so heap and the rest stay below the limit with room for threads.
# - A JVM out of memory exits, so the restart policy starts a clean one instead of leaving a broken server up.
# - The timezone is the JVM's default, read from TZ.
# - The transaction node id names this one server to the transaction manager; a second server sharing the database
#   would need its own.
# GC_LOG=false keeps standalone.sh from writing GC logs to a file; LAUNCH_JBOSS_IN_BACKGROUND makes it pass the
# container's stop signal to the JVM and wait for it, so WildFly shuts down cleanly.
ENV EJBCA_JAVA_OPTS="-Xms2g -Xmx2g -XX:+AlwaysPreTouch -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m -XX:MaxDirectMemorySize=128m -XX:+ExitOnOutOfMemoryError -Djava.net.preferIPv4Stack=false -Djava.net.preferIPv6Addresses=true -Djava.awt.headless=true -Djboss.modules.system.pkgs=org.jboss.byteman -Djboss.tx.node.id=1 -Dhttps.protocols=TLSv1.2,TLSv1.3 -Djdk.tls.client.protocols=TLSv1.2,TLSv1.3 -Djdk.tls.ephemeralDHKeySize=2048" \
    GC_LOG=false \
    LAUNCH_JBOSS_IN_BACKGROUND=true \
    JBOSS_HOME=/opt/wildfly \
    EJBCA_HOME=/opt/ejbca

USER ejbca
WORKDIR /opt/wildfly
EXPOSE 80 443
ENTRYPOINT ["/entrypoint.sh"]
