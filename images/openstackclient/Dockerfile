# The OpenStack client with its Trove and Barbican commands, from Debian's own signed packages so one image runs on
# Apple silicon, amd64 and ppc64le; no maintained published image carries both plugins for arm64.
FROM docker.io/library/debian:trixie

# The build fails unless the client runs and both plugins' commands are registered, which a package that installed
# without its entry points would not satisfy.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-openstackclient python3-troveclient python3-barbicanclient ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && openstack --version \
 && openstack help database instance create > /dev/null \
 && openstack help secret store > /dev/null

# openstacksdk reads /etc/openstack/clouds.yaml, so a run is
#   container run --rm -v ~/.config/openstack:/etc/openstack:ro <image> --os-cloud infra server list
ENTRYPOINT ["openstack"]
