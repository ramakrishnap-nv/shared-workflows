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
GITHUB_REPOSITORY="rapidsai/cuvs"
GITHUB_RUN_ATTEMPT="1"
GITHUB_RUN_ID="1234"
GITHUB_SHA="0123456789012345678901234567890123456789"
GITHUB_WORKFLOW_REF="rapidsai/cuvs/.github/workflows/build.yaml@refs/heads/release/26.08"
export GITHUB_OUTPUT
RELEASE_ARTIFACTS="$(jq -cn '[{path: "cuvs-java-*.jar", sbom: "cuvs-java-*.spdx.json", provenance: "cuvs-java-*.provenance.jsonl"}]')"
RELEASE_MANIFEST_NAME="release-build-output.json"
RELEASE_METADATA_NAME="release-build-metadata.json"
RELEASE_OUTPUT_DIRECTORY="${bundle_directory}"
RELEASE_PACKAGE="$(jq -cn '{ecosystem: "maven", name: "ai.rapids:cuvs-java", version: "26.08.0"}')"
RELEASE_SOURCE_ARTIFACT_NAME="cuvs-java-cuda12.9.1"
RELEASE_UNIT="maven:cuvs-java"
export GITHUB_REPOSITORY GITHUB_RUN_ATTEMPT GITHUB_RUN_ID GITHUB_SHA GITHUB_WORKFLOW_REF
export RELEASE_ARTIFACTS RELEASE_MANIFEST_NAME RELEASE_METADATA_NAME RELEASE_OUTPUT_DIRECTORY RELEASE_PACKAGE
export RELEASE_SOURCE_ARTIFACT_NAME RELEASE_UNIT

"${repository_root}/.github/actions/release-build-output/materialize.sh"

manifest_path="${bundle_directory}/release-build-output.json"
metadata_path="${bundle_directory}/release-build-metadata.json"
jq -e '
  .schema_version == 1
  and .producer == "release-platform"
  and (.artifacts | length == 1)
  and .artifacts[0].unit_id == "maven:cuvs-java"
  and .artifacts[0].path == "cuvs-java-26.08.0.jar"
  and .artifacts[0].package.name == "ai.rapids:cuvs-java"
' "${manifest_path}" >/dev/null
jq -e '
  .schema_version == 1
  and .producer == "shared-workflows"
  and .release_unit == "maven:cuvs-java"
  and .source_artifact == "cuvs-java-cuda12.9.1"
  and .build_output_manifest == "release-build-output.json"
  and .build_environment.repository == "rapidsai/cuvs"
  and .metadata == {}
' "${metadata_path}" >/dev/null
grep -Fx "manifest-path=${manifest_path}" "${GITHUB_OUTPUT}"
grep -Fx "metadata-path=${metadata_path}" "${GITHUB_OUTPUT}"
