# rancher/hardened-build-base

This repository holds the Dockerfiles and builds scripts for [rancher/hardened-build-base](https://hub.docker.com/r/rancher/hardened-build-base) Docker images. The `x86_64` image contains a Go compiler with FIPS 140-2 compliant crypto module, [GoBoring](https://github.com/golang/go/tree/dev.boringcrypto/misc/boring), used for [compiling rke2 components](https://docs.rke2.io/security/fips_support/#fips-support-in-cluster-components).

Supported architectures

- [x86_64/amd64, arm64](Dockerfile)

## Build

```sh
TAG=v1.20.3b1 make
```

### Go Module Overrides

The image includes `go-mod-replacer` and the policy from
[global_overrides.json](global_overrides.json). The tool applies overrides during
the image build; it does not open PRs or require a repository registration.

Run it from the upstream module directory, before downloading dependencies or
building. For example, migrate the override step in
[image-build-livenessprobe](https://github.com/rancher/image-build-livenessprobe/blob/master/Dockerfile)
to:

```dockerfile
COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-replacer ./go-mod-overrides
RUN go mod download
```

Use a build-base image version containing the new tool. `go-mod-replacer`
defaults to `./go-mod-overrides`; a missing local file still allows global
overrides to run. Use `-local FILE` to select a local file or `-global FILE`
to supply another policy.

Local files accept only `-replace module=replacement` or
`-replace=module=replacement` entries, with optional versions, comments, and blank
lines. Other directives are rejected before any edits are applied.

Local replacements are applied first and always take precedence. Global targets
are best-effort minimum bumps for required modules below their policy target,
skipping modules named in local replacements and modules with existing
replacements. Declared versions at or above the target are preserved; workspace
mode compares the highest requirement across its members. Dependency versions
are read from requirements declared in `go.mod`, not the full transitive
dependency graph.

Compiler compatibility is checked separately using `go env GOVERSION`, which
reports the running Go toolchain, not the `go` directive in `go.mod`. A global
bump is reported and skipped if that compiler is below the policy's `minimumGo`,
without blocking other compatible bumps.

In module mode, the tool runs `go mod tidy` after both sets of overrides and
`go mod vendor` if a vendor directory exists. A local `go.work` enables workspace
mode unless `GOWORK=off`; `--workspace` can enable it explicitly. Workspace mode
edits `go.work`, skips tidy, and runs `go work vendor` if a vendor directory exists.

[scripts/go-mod-overrides.sh](scripts/go-mod-overrides.sh) remains available for
unmigrated repositories and only applies their local overrides. Replace that
script invocation with `go-mod-replacer` to enable the global policy.

### Versioning

Starting from v1.19.0 dev.boringcrypto branch has been moved to the main branch behind GOEXPERIMENT variable, so the image-build-base will be adding `GOEXPERIMENT=boringcrypto` to `scripts/go-build-static.sh` script, however the build will still retain the same versionining using the `<Go version>b<BoringCrypto version>` pattern.
