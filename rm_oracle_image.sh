#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# rm_oracle_image.sh – Removes the local Oracle image and related containers.
# ---------------------------------------------------------------------------
set -euo pipefail

ORACLE_VERSION=${ORACLE_VERSION:-19.3.0}
ORACLE_EDITION=${ORACLE_EDITION:-ee}
IMAGE_TAG="oracle/database:${ORACLE_VERSION}-${ORACLE_EDITION}"

# Stop and remove any containers based on this image.
for id in $(docker ps -a --filter="ancestor=${IMAGE_TAG}" --format '{{.ID}}'); do
  echo "Removing container $id (based on ${IMAGE_TAG})"
  docker rm -f "$id"
done

# Remove the image itself.
if docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "Removing image ${IMAGE_TAG}"
  docker rmi "${IMAGE_TAG}"
else
  echo "Image ${IMAGE_TAG} not found – nothing to remove."
fi
