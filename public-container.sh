#!/usr/bin/env bash

# Resolve the actual public container ID. Docker Compose can prepend a project
# name on some Ubuntu hosts, so do not assume the configured container name is
# always the runtime name.
resolve_public_container() {
  local configured_name="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
  local container_id=""

  if "${DOCKER_BIN}" inspect "${configured_name}" >/dev/null 2>&1; then
    printf '%s\n' "${configured_name}"
    return 0
  fi

  container_id="$("${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml ps -aq open-webui-public 2>/dev/null | head -n1 || true)"
  if [ -n "${container_id}" ]; then
    printf '%s\n' "${container_id}"
    return 0
  fi

  return 1
}

ensure_public_container() {
  local container=""

  container="$(resolve_public_container || true)"
  if [ -z "${container}" ]; then
    echo "Creating the public container..." >&2
    "${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml up -d open-webui-public >&2
    container="$(resolve_public_container || true)"
  fi

  if [ -z "${container}" ]; then
    echo "Unable to find the public container after Docker Compose started it." >&2
    return 1
  fi

  if [ "$("${DOCKER_BIN}" inspect -f '{{.State.Running}}' "${container}")" != "true" ]; then
    echo "Starting the existing public container..." >&2
    "${DOCKER_BIN}" start "${container}" >&2
  fi

  printf '%s\n' "${container}"
}
