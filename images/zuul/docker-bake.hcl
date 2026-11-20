// Zuul's components for ppc64le. Zuul's Dockerfile names its Python base images as stages so a downstream build can
// replace them through named contexts; here they are OpenDev's own python-base and python-builder recipes built for
// the Python of the images-ppc64le index, which publishes none for ppc64le.

variable "VERSION" {}
variable "PYTHON_VERSION" {}
variable "REGISTRY" {}
variable "SOURCE" {}
variable "OPENSHIFT_URL" {}
variable "OPENSHIFT_SHA" {}

target "python-base" {
  context   = "system-config/docker/python-base"
  args      = { PYTHON_VERSION = PYTHON_VERSION, DEBIAN_VERSION = "trixie" }
  platforms = ["linux/ppc64le"]
}

target "python-builder" {
  context   = "system-config/docker/python-builder"
  args      = { PYTHON_VERSION = PYTHON_VERSION, DEBIAN_VERSION = "trixie" }
  platforms = ["linux/ppc64le"]
}

target "_zuul" {
  context = "zuul"
  contexts = {
    "quay.io/opendevorg/python-base:${PYTHON_VERSION}-trixie"    = "target:python-base"
    "quay.io/opendevorg/python-builder:${PYTHON_VERSION}-trixie" = "target:python-builder"
  }
  args      = { PYTHON_VERSION = PYTHON_VERSION, OPENSHIFT_URL = OPENSHIFT_URL, OPENSHIFT_SHA = OPENSHIFT_SHA }
  labels    = { "org.opencontainers.image.source" = SOURCE }
  platforms = ["linux/ppc64le"]
}

target "zuul-scheduler" {
  inherits = ["_zuul"]
  target   = "zuul-scheduler"
  tags     = ["${REGISTRY}/zuul-scheduler:${VERSION}"]
}

target "zuul-executor" {
  inherits = ["_zuul"]
  target   = "zuul-executor"
  tags     = ["${REGISTRY}/zuul-executor:${VERSION}"]
}

target "zuul-web" {
  inherits = ["_zuul"]
  target   = "zuul-web"
  tags     = ["${REGISTRY}/zuul-web:${VERSION}"]
}

target "zuul-launcher" {
  inherits = ["_zuul"]
  target   = "zuul-launcher"
  tags     = ["${REGISTRY}/zuul-launcher:${VERSION}"]
}

group "default" {
  targets = ["zuul-scheduler", "zuul-executor", "zuul-web", "zuul-launcher"]
}
