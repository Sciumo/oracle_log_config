#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create_oracle_image.sh – Prepare and (optionally) build a local Oracle
#                          Database Podman image using Oracle's public build
#                          scripts.  NOTHING is executed until the user has
#                          been shown the exact command line and gives an
#                          explicit yes.
# ---------------------------------------------------------------------------
# Usage:  ORACLE_PWD=MySecret ./create_oracle_image.sh
#
# Environment (override as needed):
#   ORACLE_VERSION   – 19.3.0 | 21.3.0 | 23.2 etc.   (default 19.3.0)
#   ORACLE_EDITION   – ee | xe | se2                  (default ee)
#   REPO_DIR         – clone path for repo            (default ./oracle-docker-images)
#   ORACLE_PWD       – SYS & SYSTEM password          (default Oradoc_db1)
#   AUTO_BUILD       – "yes" to skip confirmation     (default "no")
#   CONTAINER_ENGINE – podman | docker                (default podman)
# ---------------------------------------------------------------------------
set -euo pipefail

ORACLE_VERSION=${ORACLE_VERSION:-19.3.0}
ORACLE_EDITION=${ORACLE_EDITION:-ee}     # ee | xe | se2
IMAGE_TAG="oracle/database:${ORACLE_VERSION}-${ORACLE_EDITION}"
REPO_DIR=${REPO_DIR:-$(pwd)/oracle-docker-images}
ORACLE_PWD=${ORACLE_PWD:-Oradoc_db1}
AUTO_BUILD=${AUTO_BUILD:-no}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}

# Check for container engine
if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
  echo "ERROR: $CONTAINER_ENGINE is required but not installed." >&2
  echo "Install with: sudo dnf install podman (RHEL/Fedora) or sudo apt install podman (Ubuntu)" >&2
  exit 1
fi

# For podman, ensure we can run rootless
if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
  if ! podman info >/dev/null 2>&1; then
    echo "ERROR: Podman is not properly configured for rootless operation." >&2
    echo "Run: podman machine init && podman machine start" >&2
    exit 1
  fi
fi

echo "Using container engine: $CONTAINER_ENGINE"

# Clone or update Oracle's docker-images repo
if [[ ! -d "$REPO_DIR" ]]; then
  echo "Cloning Oracle docker-images repo to $REPO_DIR …"
  git clone --depth 1 https://github.com/oracle/docker-images.git "$REPO_DIR"
else
  echo "Updating existing repo at $REPO_DIR …"
  git -C "$REPO_DIR" pull --ff-only
fi

BUILD_ROOT="$REPO_DIR/OracleDatabase/SingleInstance/dockerfiles"
BUILD_SCRIPT="$BUILD_ROOT/buildContainerImage.sh"

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "ERROR: buildContainerImage.sh not found in $BUILD_ROOT" >&2
  echo "Repo layout may have changed; verify manually." >&2
  exit 1
fi

chmod +x "$BUILD_SCRIPT"

# Determine the sub‑folder that must hold the installer zip(s)
INSTALLER_DIR="$BUILD_ROOT/${ORACLE_VERSION%%.*}.$(echo "$ORACLE_VERSION" | cut -d. -f2).0"
if [[ ! -d "$INSTALLER_DIR" ]]; then
  echo "ERROR: Expected installer directory $INSTALLER_DIR not found." >&2
  echo "Oracle may not publish a template for $ORACLE_VERSION; check the repo." >&2
  exit 1
fi

# Each edition has its own package list – pull from Dockerfile via grep
required_pkgs=( $(grep -oE 'LINUX\.X64_[0-9]{6,}_[a-zA-Z0-9_]+\.zip' "$INSTALLER_DIR/Dockerfile" | sort -u) )

missing_pkgs=()
for p in "${required_pkgs[@]}"; do
  [[ -f "$INSTALLER_DIR/$p" ]] || missing_pkgs+=("$p")
done

if (( ${#missing_pkgs[@]} )); then
  echo -e "\nThe following installer zip(s) are required but NOT present in $INSTALLER_DIR:" >&2
  for p in "${missing_pkgs[@]}"; do echo "  • $p"; done
  cat <<EOM

Oracle's license forbids automatic download.  Please fetch each file from
https://www.oracle.com/database/technologies/ using your OTN account, accept
the click‑through license, and place the zip(s) in the directory shown above.

TIP: Consider using Oracle Container Registry instead:
  podman login container-registry.oracle.com
  podman pull container-registry.oracle.com/database/enterprise:${ORACLE_VERSION}

Then rerun this script.
EOM
  exit 1
fi

echo -e "\nBuild Script: $BUILD_SCRIPT"

# Set CONTAINER_RUNTIME environment variable for Oracle's build script
export CONTAINER_RUNTIME="$CONTAINER_ENGINE"

cmd=("$BUILD_SCRIPT" -v "$ORACLE_VERSION" -e "${ORACLE_EDITION^^}" -o "--build-arg ORACLE_PWD=$ORACLE_PWD")
echo "Proposed command:"; printf '  %q ' "${cmd[@]}"; echo -e "\n"
echo "Container engine: $CONTAINER_ENGINE"

if [[ "$AUTO_BUILD" != "yes" ]]; then
  read -rp "Proceed with build? [y/N] " ans
  [[ ${ans,,} == y* ]] || { echo "Aborted by user."; exit 0; }
fi

pushd "$BUILD_ROOT" >/dev/null
"${cmd[@]}"
status=$?
popd >/dev/null

if [[ $status -ne 0 ]]; then
  echo "ERROR: Oracle build script exited with status $status" >&2
  exit $status
fi

# Verify image exists
if $CONTAINER_ENGINE image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "✅ Oracle image $IMAGE_TAG is now available locally."
  echo "Run with: $CONTAINER_ENGINE run -d --name oracle-db -p 1521:1521 -p 5500:5500 $IMAGE_TAG"
else
  echo "ERROR: Expected image $IMAGE_TAG not found after build." >&2
  exit 1
fi