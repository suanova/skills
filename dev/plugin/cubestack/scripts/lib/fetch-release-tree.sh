#!/usr/bin/env bash
# Fetch a 2.1+ release/snapshot tree with the tree's own fetch-offline.sh.
#
# The 2.0 CLI only ships deployments/scripts/tools/offline/fetch-offline-from-minio.sh;
# 2.1 removed it and publishes fetch-offline.sh with each release prefix. Args:
#   $1 version (release or snapshot name)
#   $2 destination root (<root>/<version> is created)
#   $3 values file with MINIO_EP / MINIO_AK / MINIO_SK
#   $4 line (e.g. 2.1; derived from the version by the caller)
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
  echo "FAIL: auth: mc alias set for $MINIO_EP"
  exit 16
fi

# mc commands take ALIAS/BUCKET/KEY, not s3:// URIs; the released fetch-offline.sh
# still needs the s3:// form, so keep both.
mc_path() {
  local rest="${1#s3://}"
  printf '%s/%s' "$alias_name" "$rest"
}

# auth, transport or other — the caller maps the first two to different recoveries.
mc_error_kind() {
  case "$1" in
    *AccessDenied*|*403*|*SignatureDoesNotMatch*|*InvalidAccessKeyId*) echo auth ;;
    *"Unable to connect"*|*timeout*|*refused*|*unreachable*|*"no such host"*|*network*) echo transport ;;
    *) echo other ;;
  esac
}

store=s3://cubestack-installer/release-store
if ! out="$(mc ls "$(mc_path "$store")/" 2>&1)"; then
  case "$(mc_error_kind "$out")" in
    auth)
      echo "FAIL: auth: cannot access $store: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      exit 16
      ;;
    *)
      echo "FAIL: transport: cannot access $store: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      exit 17
      ;;
  esac
fi

prefix=""
for cand in \
  "$store/lines/$line/releases/$rel" \
  "$store/lines/$line/snapshots/$rel" \
  "s3://cubestack-installer/offline-packages/$line/$rel"; do
  if out="$(mc stat "$(mc_path "$cand/fetch-offline.sh")" 2>&1)"; then
    prefix="$cand"
    break
  fi
  case "$(mc_error_kind "$out")" in
    auth)
      echo "FAIL: auth: probing $cand: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      exit 16
      ;;
    transport)
      echo "FAIL: transport: probing $cand: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      exit 17
      ;;
  esac
done
[ -n "$prefix" ] || {
  echo "FAIL: no release/snapshot prefix for $rel (line $line)"
  exit 13
}

tmp_script="$(mktemp "${TMPDIR:-/tmp}/cubestack-fetch-offline.XXXXXX")" || {
  echo "FAIL: cannot create a temporary fetch script"
  exit 14
}
if ! out="$(mc cp "$(mc_path "$prefix/fetch-offline.sh")" "$tmp_script" 2>&1)"; then
  case "$(mc_error_kind "$out")" in
    auth)
      echo "FAIL: auth: downloading fetch-offline.sh from $prefix: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      rm -f "$tmp_script"
      exit 16
      ;;
    transport)
      echo "FAIL: transport: downloading fetch-offline.sh from $prefix: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      rm -f "$tmp_script"
      exit 17
      ;;
    *)
      echo "FAIL: could not download fetch-offline.sh from $prefix: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      rm -f "$tmp_script"
      exit 14
      ;;
  esac
fi
chmod +x "$tmp_script"

case "$prefix" in
  */offline-packages/*)
    pkg="/tmp/cubestack-pkg-$rel"
    mkdir -p "$pkg"
    if bash "$tmp_script" \
      --source "$prefix" --package-dir "$pkg" \
      --dest "$root/$rel" --all --verify \
      --mc-alias "$alias_name" --jobs 8; then
      rm -f "$tmp_script"
      exit 0
    fi
    # Release trees before #188 cannot populate an empty --package-dir from
    # --source; fetch the package with mc, then assemble from the local dir.
    echo "falling back to mc cp for $prefix"
    rm -rf "$pkg"
    mkdir -p "$pkg"
    if ! out="$(mc cp --recursive "$(mc_path "$prefix")/" "$pkg/" 2>&1)"; then
      echo "FAIL: transport: downloading $prefix with mc: $(printf '%s' "$out" | head -1 | cut -c1-120)"
      rm -f "$tmp_script"
      exit 15
    fi
    [ -f "$pkg/fetch-offline.sh" ] || cp "$tmp_script" "$pkg/fetch-offline.sh"
    bash "$pkg/fetch-offline.sh" \
      --package-dir "$pkg" --dest "$root/$rel" --all --verify
    rc=$?
    rm -f "$tmp_script"
    exit "$rc"
    ;;
  *)
    bash "$tmp_script" \
      --source "$prefix" --store-root "$store" \
      --mc-alias "$alias_name" --dest "$root/$rel" --verify
    rc=$?
    rm -f "$tmp_script"
    exit "$rc"
    ;;
esac
