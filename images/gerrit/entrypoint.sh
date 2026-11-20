#!/bin/bash
# Runs a prepared site and nothing else: the site is initialised, given its plugins and reindexed by a separate run of
# gerrit.war, so a missing file means the site was never prepared or its volume is not mounted, and Gerrit must not
# start on it.
set -euo pipefail

SITE=/var/gerrit

for file in etc/gerrit.config bin/gerrit.sh; do
  [ -f "$SITE/$file" ] || { echo "$SITE/$file is missing: prepare the site before running Gerrit" >&2; exit 1; }
done

exec "$SITE/bin/gerrit.sh" run
