//go:build mage

package main

import "github.com/grafana/grafana-plugin-sdk-go/build"

func LinuxPPC64LE() error {
	return build.Build{}.Custom("linux", "ppc64le")
}
