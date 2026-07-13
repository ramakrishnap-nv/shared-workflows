#!/usr/bin/env bash
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

bundle_directory="${temporary_directory}/bundle"
mkdir -p "${bundle_directory}"
printf '%s\n' jar >"${bundle_directory}/cuvs-java-26.08.0.jar"
printf '%s\n' sbom >"${bundle_directory}/cuvs-java-26.08.0.spdx.json"
printf '%s\n' provenance >"${bundle_directory}/cuvs-java-26.08.0.provenance.jsonl"

GITHUB_OUTPUT="${temporary_directory}/github-output"
export GITHUB_OUTPUT
RELEASE_ARTIFACTS="$(jq -cn '[{path: "cuvs-java-*.jar", sbom: "cuvs-java-*.spdx.json", provenance: "cuvs-java-*.provenance.jsonl"}]')"
RELEASE_MANIFEST_NAME="release-build-output.json"
RELEASE_OUTPUT_DIRECTORY="${bundle_directory}"
RELEASE_PACKAGE="$(jq -cn '{ecosystem: "maven", name: "ai.rapids:cuvs-java", version: "26.08.0"}')"
RELEASE_UNIT="maven:cuvs-java"
export RELEASE_ARTIFACTS RELEASE_MANIFEST_NAME RELEASE_OUTPUT_DIRECTORY RELEASE_PACKAGE RELEASE_UNIT

"${repository_root}/.github/actions/release-build-output/materialize.sh"

manifest_path="${bundle_directory}/release-build-output.json"
jq -e '
  .schema_version == 1
  and .producer == "release-platform"
  and (.artifacts | length == 1)
  and .artifacts[0].unit_id == "maven:cuvs-java"
  and .artifacts[0].path == "cuvs-java-26.08.0.jar"
  and .artifacts[0].package.name == "ai.rapids:cuvs-java"
' "${manifest_path}" >/dev/null
grep -Fx "manifest-path=${manifest_path}" "${GITHUB_OUTPUT}"
