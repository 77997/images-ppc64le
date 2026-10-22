FROM registry.access.redhat.com/ubi8/ubi AS freeipmi
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG FREEIPMI_VERSION
RUN dnf install -y gcc make libgcrypt-devel
WORKDIR /src
RUN curl -fsSL "https://ftp.gnu.org/gnu/freeipmi/freeipmi-${FREEIPMI_VERSION}.tar.gz" | tar -xz --strip-components=1
RUN ./configure --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc --localstatedir=/var \
 && make -j"$(nproc)" \
 && make install DESTDIR=/rootfs

FROM --platform=$BUILDPLATFORM registry.access.redhat.com/ubi8/ubi AS exporter
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG IPMI_EXPORTER_VERSION
WORKDIR /src
RUN curl -fsSL "https://github.com/prometheus-community/ipmi_exporter/releases/download/v${IPMI_EXPORTER_VERSION}/ipmi_exporter-${IPMI_EXPORTER_VERSION}.linux-ppc64le.tar.gz" | tar -xz --strip-components=1

FROM registry.access.redhat.com/ubi8/ubi-minimal
COPY --from=freeipmi /rootfs/usr/sbin/ /usr/sbin/
COPY --from=freeipmi /rootfs/usr/lib64/ /usr/lib64/
COPY --from=freeipmi /rootfs/etc/freeipmi/ /etc/freeipmi/
COPY --from=exporter /src/ipmi_exporter /usr/bin/ipmi_exporter
ENTRYPOINT ["/usr/bin/ipmi_exporter"]
