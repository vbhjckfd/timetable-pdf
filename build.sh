#!/bin/sh
set -e

IMAGE=gcr.io/timetable-252615/timetable-pdf

# Cloud Run rejects an OCI image index ("Container manifest type
# 'application/vnd.oci.image.index.v1+json' must support amd64/linux"), and
# that is exactly what buildx produces by default, because it attaches
# provenance and SBOM attestations as extra manifests. Turn those off, force
# docker media types, and push straight from the builder so a single amd64
# image manifest is what lands in the registry.
#
# --platform matters on its own: without it a build on an arm64 machine pushes
# an arm64 image that Cloud Run will refuse for a different reason.
docker buildx build \
    --platform linux/amd64 \
    --provenance=false \
    --sbom=false \
    --output "type=image,name=$IMAGE,push=true,oci-mediatypes=false" \
    .
