# FBC Catalog Template

This directory contains the **template** for the ptp-operator File-Based Catalog
(FBC). It is used by the CI workflow
(`.github/workflows/ptp-operator-build-catalog-image.yaml`) to generate the
final `catalog/` directory at build time.

## How it works

1. The CI workflow checks out every `release-*` branch and `main`.
2. It builds and pushes an **operator image** and a **bundle image** for each.
3. In the catalog job it uses `opm render` to expand every bundle image into FBC
   entries, appends the channel definition from `channel-template.yaml`, and
   validates the result with `opm validate`.
4. The validated catalog directory is packaged into the catalog image using
   `catalog-publish.Dockerfile`.

## Local testing

```bash
# Build a single-version catalog (current branch only):
make catalog-build

# Build the multi-version catalog locally (requires all bundle images in a registry):
make ghcr-catalog-build
```
