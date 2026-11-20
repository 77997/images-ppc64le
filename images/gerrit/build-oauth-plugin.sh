#!/bin/bash
# Builds the OAuth plugin's Entra ID provider (oauth-azure) against the Gerrit release of release.env and writes it to
# the path given. Its published release jars were built from Gerrit pre-release trees, so it is built here from the
# pinned commits, and the build fails unless the jar names that release's plugin API and the plugin's own classes.
# It is Java bytecode, so one amd64 build serves both architectures.
set -euo pipefail

OUT="$(realpath -m "$1")"
. "$(dirname "$0")/release.env"
WORK="$(mktemp -d)"

curl -fsSL -o "$WORK/bazelisk" "https://github.com/bazelbuild/bazelisk/releases/download/v$BAZELISK_VERSION/bazelisk-linux-amd64"
echo "$BAZELISK_SHA256  $WORK/bazelisk" | sha256sum -c -
chmod 755 "$WORK/bazelisk"

# The full tag is cloned because Gerrit stamps Gerrit-ApiVersion from git describe of its tree.
git -c advice.detachedHead=false clone --branch "v$GERRIT_VERSION" --depth 1 --recurse-submodules --shallow-submodules \
  https://gerrit.googlesource.com/gerrit "$WORK/gerrit"
[ "$(git -C "$WORK/gerrit" rev-parse HEAD)" = "$GERRIT_COMMIT" ] || { echo "Gerrit's tag v$GERRIT_VERSION is not $GERRIT_COMMIT"; exit 1; }
git clone https://github.com/davido/gerrit-oauth-provider "$WORK/gerrit/plugins/oauth"
git -C "$WORK/gerrit/plugins/oauth" -c advice.detachedHead=false checkout --detach "$OAUTH_COMMIT"
rm "$WORK/gerrit/plugins/external_plugin_deps.MODULE.bazel"
ln -s oauth/external_plugin_deps.MODULE.bazel "$WORK/gerrit/plugins/external_plugin_deps.MODULE.bazel"

TARGET=plugins/oauth/src/main/java/com/googlesource/gerrit/plugins/oauth/azure
(cd "$WORK/gerrit" && "$WORK/bazelisk" build "//$TARGET:oauth-azure")
JAR="$WORK/gerrit/bazel-bin/$TARGET/oauth-azure.jar"

MANIFEST="$(unzip -p "$JAR" META-INF/MANIFEST.MF | tr -d '\r')"
echo "$MANIFEST"
grep -qx "Gerrit-ApiVersion: $GERRIT_VERSION" <<<"$MANIFEST" || { echo "The jar does not name the plugin API $GERRIT_VERSION"; exit 1; }
grep -qx 'Gerrit-PluginName: gerrit-oauth-provider' <<<"$MANIFEST" || { echo "The jar does not name the plugin gerrit-oauth-provider"; exit 1; }
grep -qx 'Gerrit-Module: com.googlesource.gerrit.plugins.oauth.azure.AzurePluginModule' <<<"$MANIFEST" \
  || { echo "The jar does not name the Entra ID module"; exit 1; }
! grep -q -- '-dirty' <<<"$MANIFEST" || { echo "The jar was built from a changed tree"; exit 1; }
# The listing is read whole, since grep -q leaving a pipe early fails it under pipefail.
LISTING="$(unzip -l "$JAR")"
grep -q 'com/googlesource/gerrit/plugins/oauth/azure/AzureActiveDirectoryService.class' <<<"$LISTING" \
  || { echo "The jar holds no Entra ID provider"; exit 1; }

install -m 644 "$JAR" "$OUT"
sha256sum "$OUT"
