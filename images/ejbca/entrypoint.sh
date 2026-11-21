#!/bin/bash
# Starts WildFly with EJBCA against an existing EJBCA database, and nothing else. WildFly reads the database address
# and credentials and the TLS store passwords from these variables when it starts, so a missing one would only show
# later as a failed deployment or a listener without a certificate; the container refuses to start instead.
set -euo pipefail

for name in EJBCA_JAVA_OPTS EJBCA_DATABASE_URL EJBCA_DATABASE_USER EJBCA_DATABASE_PASSWORD EJBCA_KEYSTORE_PASSWORD \
            EJBCA_TRUSTSTORE_PASSWORD; do
  [ -n "${!name:-}" ] || { echo "$name is not set or is empty: the container's environment must name it" >&2; exit 1; }
done

# The image holds the PostgreSQL driver alone.
case "$EJBCA_DATABASE_URL" in
  jdbc:postgresql:*) ;;
  *) echo "EJBCA_DATABASE_URL is not a PostgreSQL JDBC URL (jdbc:postgresql:...)" >&2; exit 1 ;;
esac

for file in /etc/ejbca/tls/keystore.p12 /etc/ejbca/tls/truststore.p12; do
  [ -r "$file" ] || { echo "$file is missing or not readable by uid $(id -u): mount the TLS stores" >&2; exit 1; }
done

# standalone.sh stays in the foreground as the container's first process; with LAUNCH_JBOSS_IN_BACKGROUND it runs
# the JVM as its child, passes the stop signal to it and waits for WildFly to shut down.
# Only the server's JVM takes EJBCA_JAVA_OPTS, so a jboss-cli.sh run beside it keeps its own small default heap.
export JAVA_OPTS="$EJBCA_JAVA_OPTS"
exec /opt/wildfly/bin/standalone.sh
