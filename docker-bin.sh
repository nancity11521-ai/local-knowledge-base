#!/usr/bin/env bash

DOCKER_DESKTOP_BIN="/Applications/Docker.app/Contents/Resources/bin"

if [ -d "${DOCKER_DESKTOP_BIN}" ]; then
  export PATH="${DOCKER_DESKTOP_BIN}:${PATH}"
fi

find_docker_bin() {
  if command -v docker >/dev/null 2>&1; then
    command -v docker
    return 0
  fi

  if [ -x /Applications/Docker.app/Contents/Resources/bin/docker ]; then
    echo /Applications/Docker.app/Contents/Resources/bin/docker
    return 0
  fi

  return 1
}
