FROM --platform=$BUILDPLATFORM golang:trixie AS build
ARG IDRAC_EXPORTER_VERSION
RUN git clone --depth 1 --branch "v${IDRAC_EXPORTER_VERSION}" https://github.com/mrlhansen/idrac_exporter.git /src
WORKDIR /src
RUN CGO_ENABLED=0 GOOS=linux GOARCH=ppc64le make build

FROM registry.access.redhat.com/ubi8/ubi-minimal
COPY --from=build /src/idrac_exporter /usr/bin/idrac_exporter
ENTRYPOINT ["/usr/bin/idrac_exporter"]
