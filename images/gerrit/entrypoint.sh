#!/bin/bash
# Initialises the site on its first start, or when called with "init", then runs Gerrit in the foreground.
set -euo pipefail

SITE=/var/gerrit

if [ ! -f "$SITE/etc/gerrit.config" ] || [ "${1:-}" = "init" ]; then
  java -jar "$SITE/bin/gerrit.war" init --batch --install-all-plugins --no-auto-start -d "$SITE"
  java -jar "$SITE/bin/gerrit.war" reindex -d "$SITE"
  [ "${1:-}" = "init" ] && exit 0
fi

exec "$SITE/bin/gerrit.sh" run
