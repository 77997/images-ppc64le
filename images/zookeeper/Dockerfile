# Debian's own ZooKeeper, whose Java runs on POWER8; the Docker library image is built on Ubuntu, whose ppc64el
# userland targets POWER9 and faults with an illegal instruction on POWER8.
FROM docker.io/library/debian:trixie

# Debian's zkEnv.sh sets the whole classpath, which leaves out the Netty codec that TLS on the client port needs and
# the log4j binding, without which SLF4J drops every log line; the build fails if the line it replaces has changed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends zookeeper default-jre-headless netcat-openbsd \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i 's#^CLASSPATH="/etc/zookeeper/conf:/usr/share/java/zookeeper.jar"$#CLASSPATH="/etc/zookeeper/conf:/usr/share/java/zookeeper.jar:/usr/share/java/netty-codec.jar:/usr/share/java/slf4j-log4j12.jar:/usr/share/java/log4j-1.2.jar"#' /usr/share/zookeeper/bin/zkEnv.sh \
 && grep -qx 'CLASSPATH="/etc/zookeeper/conf:/usr/share/java/zookeeper.jar:/usr/share/java/netty-codec.jar:/usr/share/java/slf4j-log4j12.jar:/usr/share/java/log4j-1.2.jar"' /usr/share/zookeeper/bin/zkEnv.sh \
 && mkdir -p /data \
 && chown zookeeper:zookeeper /data

USER zookeeper
# The server logs to the console alone; JVMFLAGS stays free for the heap.
ENV SERVER_JVMFLAGS="-Dzookeeper.root.logger=INFO,CONSOLE"
ENTRYPOINT ["/usr/share/zookeeper/bin/zkServer.sh", "start-foreground"]
