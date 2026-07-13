#!/usr/bin/env bash
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.

set -euo pipefail

require_nonempty() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "${name} must be a non-empty string" >&2
    exit 1
  fi
}

require_nonempty "RELEASE_UNIT" "${RELEASE_UNIT:-}"
require_nonempty "RELEASE_OUTPUT_DIRECTORY" "${RELEASE_OUTPUT_DIRECTORY:-}"
require_nonempty "RELEASE_MANIFEST_NAME" "${RELEASE_MANIFEST_NAME:-}"
require_nonempty "RELEASE_PACKAGE" "${RELEASE_PACKAGE:-}"
require_nonempty "RELEASE_ARTIFACTS" "${RELEASE_ARTIFACTS:-}"

if [[ "${RELEASE_MANIFEST_NAME}" == */* || "${RELEASE_MANIFEST_NAME}" == .* || "${RELEASE_MANIFEST_NAME}" == *".."* ]]; then
  echo "manifest-name must be a plain filename" >&2
  exit 1
fi

if [[ ! -d "${RELEASE_OUTPUT_DIRECTORY}" ]]; then
  echo "output-directory does not exist or is not a directory: ${RELEASE_OUTPUT_DIRECTORY}" >&2
  exit 1
fi

if ! jq -e '
  type == "object"
  and (keys - ["ecosystem", "name", "version", "build", "platform"] | length == 0)
  and (.ecosystem | type == "string" and length > 0)
  and (.name | type == "string" and length > 0)
  and (.version | type == "string" and length > 0)
  and ((.build // "") | type == "string")
  and ((.platform // "") | type == "string")
' <<<"${RELEASE_PACKAGE}" >/dev/null; then
  echo "release-package must be a package object with ecosystem, name, and version" >&2
  exit 1
fi

if ! jq -e 'type == "array" and length > 0' <<<"${RELEASE_ARTIFACTS}" >/dev/null; then
  echo "release-artifacts must be a non-empty JSON array" >&2
  exit 1
fi

output_directory="$(realpath "${RELEASE_OUTPUT_DIRECTORY}")"
manifest_path="${output_directory}/${RELEASE_MANIFEST_NAME}"
temporary_manifest="$(mktemp "${output_directory}/.release-build-output.XXXXXX")"
trap 'rm -f "${temporary_manifest}"' EXIT

printf '%s\n' '{"schema_version":1,"producer":"release-platform","artifacts":[]}' >"${temporary_manifest}"

ensure_relative_pattern() {
  local field="$1"
  local pattern="$2"
  if [[ "${pattern}" == /* || "${pattern}" == */../* || "${pattern}" == ../* || "${pattern}" == *"/.." ]]; then
    echo "${field} must be a relative path inside output-directory: ${pattern}" >&2
    exit 1
  fi
}

resolve_one_file() {
  local field="$1"
  local pattern="$2"
  local -a matches=()

  ensure_relative_pattern "${field}" "${pattern}"
  while IFS= read -r match; do
    matches+=("${match}")
  done < <(compgen -G "${output_directory}/${pattern}" || true)
  if [[ "${#matches[@]}" -ne 1 || ! -f "${matches[0]:-}" ]]; then
    echo "${field} pattern must resolve to exactly one file: ${pattern}" >&2
    exit 1
  fi

  local resolved
  resolved="$(realpath "${matches[0]}")"
  if [[ "${resolved}" != "${output_directory}"/* ]]; then
    echo "${field} must resolve inside output-directory: ${pattern}" >&2
    exit 1
  fi
  printf '%s\n' "${resolved#"${output_directory}/"}"
}

shopt -s globstar nullglob
while IFS= read -r descriptor; do
  if ! jq -e '
    type == "object"
    and (keys - ["path", "sbom", "provenance", "signature", "package"] | length == 0)
    and (.path | type == "string" and length > 0)
    and (.sbom | type == "string" and length > 0)
    and (.provenance | type == "string" and length > 0)
    and ((.signature // "") | type == "string")
    and ((.package // {}) | type == "object")
    and ((.package // {} | keys - ["ecosystem", "name", "version", "build", "platform"]) | length == 0)
    and ((.package // {} | to_entries | map(.value | type == "string" and length > 0) | all))
  ' <<<"${descriptor}" >/dev/null; then
    echo "every release-artifacts entry must contain path, sbom, provenance, and optional signature/package overrides" >&2
    exit 1
  fi

  primary_path="$(resolve_one_file path "$(jq -r '.path' <<<"${descriptor}")")"
  sbom_path="$(resolve_one_file sbom "$(jq -r '.sbom' <<<"${descriptor}")")"
  provenance_path="$(resolve_one_file provenance "$(jq -r '.provenance' <<<"${descriptor}")")"
  signature_pattern="$(jq -r '.signature // empty' <<<"${descriptor}")"
  package_override="$(jq -c '.package // {}' <<<"${descriptor}")"

  package="$(jq -cn --argjson base "${RELEASE_PACKAGE}" --argjson override "${package_override}" '$base + $override')"
  artifact="$(jq -cn \
    --arg unit_id "${RELEASE_UNIT}" \
    --arg path "${primary_path}" \
    --arg sbom "${sbom_path}" \
    --arg provenance "${provenance_path}" \
    --argjson package "${package}" \
    '{unit_id: $unit_id, path: $path, sbom: $sbom, provenance: $provenance, package: $package}')"
  if [[ -n "${signature_pattern}" ]]; then
    signature_path="$(resolve_one_file signature "${signature_pattern}")"
    artifact="$(jq -c --arg signature "${signature_path}" '. + {signature: $signature}' <<<"${artifact}")"
  fi

  jq --argjson artifact "${artifact}" '.artifacts += [$artifact]' "${temporary_manifest}" >"${temporary_manifest}.next"
  mv "${temporary_manifest}.next" "${temporary_manifest}"
done < <(jq -c '.[]' <<<"${RELEASE_ARTIFACTS}")

if ! jq -e '.artifacts as $items | ($items | map([.unit_id, .path] | join("\u0000")) | unique | length) == ($items | length)' "${temporary_manifest}" >/dev/null; then
  echo "release-artifacts contains duplicate unit/path entries" >&2
  exit 1
fi

jq -S . "${temporary_manifest}" >"${manifest_path}"
echo "manifest-path=${manifest_path}" >>"${GITHUB_OUTPUT}"
