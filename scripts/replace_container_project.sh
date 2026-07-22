#!/usr/bin/env bash
set -euo pipefail

# Invoked inside the permitted interactive container shell by the fixed
# /tmp/cetc_activate.sh helper prepared by sync_to_container.sh.

incoming="${1:-}"
[[ "${incoming}" == /CETC.incoming.* ]] || {
  echo "usage: $0 /CETC.incoming.<unique>" >&2
  exit 2
}
[[ -d "${incoming}" && -f "${incoming}/CMakeLists.txt" && -f "${incoming}/DELIVERY_FILES.txt" ]] || {
  echo "incoming delivery is incomplete: ${incoming}" >&2
  exit 2
}

previous=""
if [[ -e /CETC ]]; then
  previous="/CETC.previous.$(date +%Y%m%d%H%M%S).$$"
  [[ ! -e "${previous}" ]]
  mv /CETC "${previous}"
fi

if ! mv "${incoming}" /CETC; then
  if [[ -n "${previous}" && -e "${previous}" && ! -e /CETC ]]; then
    mv "${previous}" /CETC
  fi
  echo "activation failed; previous /CETC restored when available" >&2
  exit 1
fi

if [[ -n "${previous}" ]]; then
  rm -rf -- "${previous}"
fi
rm -f -- /tmp/cetc_activate.sh
echo "[container-sync] active project: /CETC"
