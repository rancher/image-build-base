# rancher/hardened-build-base

This repository holds the Dockerfiles and builds scripts for [rancher/hardened-build-base](https://hub.docker.com/r/rancher/hardened-build-base) Docker images. The `x86_64` image contains a Go compiler with FIPS 140-2 compliant crypto module, [GoBoring](https://github.com/golang/go/tree/dev.boringcrypto/misc/boring), used for [compiling rke2 components](https://docs.rke2.io/security/fips_support/#fips-support-in-cluster-components).

Supported architectures

- [x86_64/amd64, arm64](Dockerfile)

## Build

```sh
TAG=v1.20.3b1 make
```

### Versioning

Starting from v1.19.0 dev.boringcrypto branch has been moved to the main branch behind GOEXPERIMENT variable, so the image-build-base will be adding `GOEXPERIMENT=boringcrypto` to `scripts/go-build-static.sh` script, however the build will still retain the same versionining using the `<Go version>b<BoringCrypto version>` pattern.
