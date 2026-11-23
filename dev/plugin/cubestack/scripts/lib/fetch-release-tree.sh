#!/usr/bin/env bash
# Fetch a 2.1+ release/snapshot tree with the tree's own fetch-offline.sh.
#
# The 2.0 CLI only ships deployments/scripts/tools/offline/fetch-offline-from-minio.sh;
# 2.1 removed it and publishes fetch-offline.sh with each release prefix. Args:
#   $1 version (release or snapshot name)
#   $2 destination root (<root>/<version> is created)
#   $3 values file with MINIO_EP / MINIO_AK / MINIO_SK
#   $4 line (default 2.1)
set -uo pipefail

rel=$1
root=$2
values=$3
line=${4:-2.1}

set -a
# shellcheck disable=SC1090
. "$values"
set +a

export MC_CONFIG_DIR="/tmp/mc-$$"
mkdir -p "$MC_CONFIG_DIR"
alias_name=cs-src
if ! mc alias set "$alias_name" "$MINIO_EP" "$MINIO_AK" "$MINIO_SK" >/dev/null 2>&1; then
  echo "FAIL: mc alias set for $MINIO_EP"
  exit 12
fi

store=s3://cubestack-installer/release-store
prefix=""
for cand in \
  "$store/lines/$line/releases/$rel" \
  "$store/lines/$line/snapshots/$rel" \
  "s3://cubestack-installer/offline-packages/$line/$rel"; do
  if mc stat "$cand/fetch-offline.sh" >/dev/null 2>&1; then
    prefix="$cand"
    break
  fi
done
[ -n "$prefix" ] || {
  echo "FAIL: no release/snapshot prefix for $rel (line $line)"
  exit 13
}

if ! mc cp "$prefix/fetch-offline.sh" /tmp/fetch-offline.sh >/dev/null 2>&1; then
  echo "FAIL: could not download fetch-offline.sh from $prefix"
  exit 14
fi

case "$prefix" in
  */offline-packages/*)
    pkg="/tmp/cubestack-pkg-$rel"
    mkdir -p "$pkg"
    if bash /tmp/fetch-offline.sh \
      --source "$prefix" --package-dir "$pkg" \
      --dest "$root/$rel" --all --verify \
      --mc-alias "$alias_name" --jobs 8; then
      exit 0
    fi
    # Release trees before #188 cannot populate an empty --package-dir from
    # --source; fetch the package with mc, then assemble from the local dir.
    echo "falling back to mc cp for $prefix"
    rm -rf "$pkg"
    mkdir -p "$pkg"
    mc cp --recursive "$prefix/" "$pkg/" >/dev/null 2>&1 || {
      echo "FAIL: could not download $prefix with mc"
      exit 15
    }
    [ -f "$pkg/fetch-offline.sh" ] || cp /tmp/fetch-offline.sh "$pkg/fetch-offline.sh"
    exec bash "$pkg/fetch-offline.sh" \
      --package-dir "$pkg" --dest "$root/$rel" --all --verify
    ;;
  *)
    exec bash /tmp/fetch-offline.sh \
      --source "$prefix" --store-root "$store" \
      --mc-alias "$alias_name" --dest "$root/$rel" --verify
    ;;
esac
