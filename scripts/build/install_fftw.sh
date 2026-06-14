#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

FFTW_VERSION="3.3.10"
FFTW_ARCHIVE="fftw-${FFTW_VERSION}.tar.gz"
FFTW_URL="https://fftw.org/${FFTW_ARCHIVE}"

THIRD_PARTY_ROOT="${PROJECT_ROOT}/third_party/fftw"
DIST_DIR="${THIRD_PARTY_ROOT}/dist"
SRC_DIR="${THIRD_PARTY_ROOT}/src"
BUILD_DIR="${THIRD_PARTY_ROOT}/build"
INSTALL_DIR="${THIRD_PARTY_ROOT}/install"
ARCHIVE_PATH="${DIST_DIR}/${FFTW_ARCHIVE}"
SOURCE_PATH="${SRC_DIR}/fftw-${FFTW_VERSION}"

log() {
  echo "[install-fftw] $*"
}

die() {
  echo "[install-fftw] error: $*" >&2
  exit 2
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

download_archive() {
  if [[ -f "${ARCHIVE_PATH}" ]]; then
    log "reuse archive: ${ARCHIVE_PATH}"
    return
  fi

  mkdir -p "${DIST_DIR}"

  if command -v wget >/dev/null 2>&1; then
    log "download: ${FFTW_URL}"
    wget -O "${ARCHIVE_PATH}" "${FFTW_URL}"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    log "download: ${FFTW_URL}"
    curl -L "${FFTW_URL}" -o "${ARCHIVE_PATH}"
    return
  fi

  die "neither wget nor curl is available"
}

extract_archive() {
  mkdir -p "${SRC_DIR}"
  rm -rf "${SOURCE_PATH}"
  tar -xzf "${ARCHIVE_PATH}" -C "${SRC_DIR}"
}

configure_build() {
  mkdir -p "${BUILD_DIR}"
  cd "${SOURCE_PATH}"
  ./configure \
    --prefix="${INSTALL_DIR}" \
    --disable-shared \
    --enable-static \
    --with-pic
}

build_and_install() {
  cd "${SOURCE_PATH}"
  make -j"$(nproc)"
  make install
}

main() {
  require_command tar
  require_command make
  require_command gcc

  download_archive
  extract_archive
  configure_build
  build_and_install

  [[ -f "${INSTALL_DIR}/include/fftw3.h" ]] || die "missing installed fftw3.h"
  [[ -f "${INSTALL_DIR}/lib/libfftw3.a" ]] || die "missing installed libfftw3.a"

  log "install complete: ${INSTALL_DIR}"
}

main "$@"
