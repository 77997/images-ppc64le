#!/bin/bash
# Builds the SAML plugin, which signs Gerrit in through a SAML identity provider, against the Gerrit release of
# release.env and writes it to the path given. Built on its own, the plugin compiles against the older plugin API its
# own MODULE.bazel names, so it is built inside Gerrit's tree at the pinned commits, against that release's API, and
# the build fails unless the jar names that release's plugin API, the saml plugin and the plugin's pinned commit from a
# clean tree, and holds its filter, its module and the pac4j SAML client it bundles. It is Java bytecode, so one amd64
# build serves both architectures.
set -euo pipefail

OUT="$(realpath -m "$1")"
. "$(dirname "$0")/release.env"
WORK="$(mktemp -d)"

curl -fsSL -o "$WORK/bazelisk" "https://github.com/bazelbuild/bazelisk/releases/download/v$BAZELISK_VERSION/bazelisk-linux-amd64"
echo "$BAZELISK_SHA256  $WORK/bazelisk" | sha256sum -c -
chmod 755 "$WORK/bazelisk"

# The tree needs its submodules, since jgit is a module of its build. Gerrit-ApiVersion is stamped with the release
# that the tree's tools/bazlets.MODULE.bazel names.
git -c advice.detachedHead=false clone --branch "v$GERRIT_VERSION" --depth 1 --recurse-submodules --shallow-submodules \
  https://gerrit.googlesource.com/gerrit "$WORK/gerrit"
[ "$(git -C "$WORK/gerrit" rev-parse HEAD)" = "$GERRIT_COMMIT" ] || { echo "Gerrit's tag v$GERRIT_VERSION is not $GERRIT_COMMIT"; exit 1; }
# Implementation-Version is stamped with git describe of the plugin's own clone, which is checked below.
git clone https://gerrit.googlesource.com/plugins/saml "$WORK/gerrit/plugins/saml"
git -C "$WORK/gerrit/plugins/saml" -c advice.detachedHead=false checkout --detach "$SAML_COMMIT"
# The plugin's fragment wires its module into the tree's build, and its lock file pins every library it bundles with
# its checksum: OpenSAML and Shibboleth's own libraries from Shibboleth's Maven repository, which Maven Central does not
# hold, and the rest from Maven Central.
rm "$WORK/gerrit/plugins/external_plugin_deps.MODULE.bazel"
ln -s saml/external_plugin_deps.MODULE.bazel "$WORK/gerrit/plugins/external_plugin_deps.MODULE.bazel"

(cd "$WORK/gerrit" && "$WORK/bazelisk" build //plugins/saml:saml)
JAR="$WORK/gerrit/bazel-bin/plugins/saml/saml.jar"

MANIFEST="$(unzip -p "$JAR" META-INF/MANIFEST.MF | tr -d '\r')"
echo "$MANIFEST"
grep -qx "Gerrit-ApiVersion: $GERRIT_VERSION" <<<"$MANIFEST" || { echo "The jar does not name the plugin API $GERRIT_VERSION"; exit 1; }
grep -qx 'Gerrit-PluginName: saml' <<<"$MANIFEST" || { echo "The jar does not name the plugin saml"; exit 1; }
! grep -q -- '-dirty' <<<"$MANIFEST" || { echo "The jar was built from a changed tree"; exit 1; }
# Implementation-Version is the plugin's abbreviated commit, preceded by its nearest v tag and the distance from it
# once such a tag exists.
DESCRIBED='^(.+-g)?([0-9a-f]{7,40})$'
VERSION="$(sed -n 's/^Implementation-Version: //p' <<<"$MANIFEST")"
[[ "$VERSION" =~ $DESCRIBED ]] || { echo "The jar names no plugin commit"; exit 1; }
[[ "$SAML_COMMIT" == "${BASH_REMATCH[2]}"* ]] || { echo "The jar was built from ${BASH_REMATCH[2]}, not $SAML_COMMIT"; exit 1; }
# The listing is read whole, since grep -q leaving a pipe early fails it under pipefail.
LISTING="$(unzip -l "$JAR")"
for class in com/googlesource/gerrit/plugins/saml/SamlWebFilter.class com/googlesource/gerrit/plugins/saml/Module.class \
             org/pac4j/saml/client/SAML2Client.class; do
  grep -q " $class\$" <<<"$LISTING" || { echo "The jar holds no $class"; exit 1; }
done

install -m 644 "$JAR" "$OUT"
sha256sum "$OUT"
