# rancher/hardened-build-base

This repository holds the Dockerfiles and builds scripts for [rancher/hardened-build-base](https://hub.docker.com/r/rancher/hardened-build-base) Docker images. The `x86_64` image contains a Go compiler with FIPS 140-2 compliant crypto module, [GoBoring](https://github.com/golang/go/tree/dev.boringcrypto/misc/boring), used for [compiling rke2 components](https://docs.rke2.io/security/fips_support/#fips-support-in-cluster-components).

Supported architectures

- [x86_64/amd64](Dockerfile.amd64)
- [arm64](Dockerfile.arm64)
- [s390x](Dockerfile.s390x)

## Build

```sh
TAG=v1.13.15b4 make
```

### Versioning

The images built within this repository use the same versioning format as [GoBoring](https://github.com/golang/go/tree/dev.boringcrypto/misc/boring#version-strings), using the `<Go version>b<BoringCrypto version>` pattern.
