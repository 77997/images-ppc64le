# Debian's own ZooKeeper, whose Java runs on POWER8; the Docker library image is built on Ubuntu, whose ppc64el
# userland targets POWER9 and faults with an illegal instruction on POWER8.
FROM docker.io/library/debian:trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends zookeeper default-jre-headless netcat-openbsd \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /data \
 && chown zookeeper:zookeeper /data

USER zookeeper
ENV ZOOCFGDIR=/etc/zookeeper/conf ZOO_LOG_DIR=/data/logs
ENTRYPOINT ["/usr/share/zookeeper/bin/zkServer.sh", "start-foreground"]
