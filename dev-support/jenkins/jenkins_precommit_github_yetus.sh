#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# SHELLDOC-IGNORE

set -e

# place ourselves in the directory containing the hbase and yetus checkouts
cd "$(dirname "$0")/../.."
echo "executing from $(pwd)"

if [[ "true" = "${DEBUG}" ]]; then
  set -x
  printenv 2>&1 | sort
fi

declare -i missing_env=0
declare -a required_envs=(
  # these ENV variables define the required API with Jenkinsfile_GitHub
  "ARCHIVE_PATTERN_LIST"
  "BUILD_URL_ARTIFACTS"
  "GITHUB_TOKEN"
  "PATCHDIR"
  "PLUGINS"
  "SOURCEDIR"
  "YETUSDIR"
)
# Validate params
for required_env in "${required_envs[@]}"; do
  if [ -z "${!required_env}" ]; then
    echo "[ERROR] Required environment variable '${required_env}' is not set."
    missing_env=${missing_env}+1
  fi
done

if [ ${missing_env} -gt 0 ]; then
  echo "[ERROR] Please set the required environment variables before invoking. If this error is " \
       "on Jenkins, then please file a JIRA about the error."
  exit 1
fi

# TODO (HBASE-23900): cannot assume test-patch runs directly from sources
TESTPATCHBIN="${YETUSDIR}/precommit/src/main/shell/test-patch.sh"

# this must be clean for every run
rm -rf "${PATCHDIR}"
mkdir -p "${PATCHDIR}"

# Gather machine information
mkdir "${PATCHDIR}/machine"
"${SOURCEDIR}/dev-support/jenkins/gather_machine_environment.sh" "${PATCHDIR}/machine"

# If CHANGE_URL is set (e.g., Github Branch Source plugin), process it.
# Otherwise exit, because we don't want HBase to do a
# full build.  We wouldn't normally do this check for smaller
# projects. :)
if [[ -z "${CHANGE_URL}" ]]; then
  echo "Full build skipped" > "${PATCHDIR}/report.html"
  exit 0
fi
# enable debug output for yetus
if [[ "true" = "${DEBUG}" ]]; then
  YETUS_ARGS+=("--debug")
fi
# If we're doing docker, make sure we don't accidentally pollute the image with a host java path
if [ -n "${JAVA_HOME}" ]; then
  unset JAVA_HOME
fi
YETUS_ARGS+=('--project=hbase-kustomize')
YETUS_ARGS+=("--patch-dir=${PATCHDIR}")
# where the source is located
YETUS_ARGS+=("--basedir=${SOURCEDIR}")
# lots of different output formats
YETUS_ARGS+=("--brief-report-file=${PATCHDIR}/brief.txt")
YETUS_ARGS+=("--console-report-file=${PATCHDIR}/console.txt")
YETUS_ARGS+=("--html-report-file=${PATCHDIR}/report.html")
# don't complain about issues on source branch
YETUS_ARGS+=('--continuous-improvement=true')
# don't worry about unrecognized options
YETUS_ARGS+=('--ignore-unknown-options=true')
# auto-kill any surefire stragglers during unit test runs
YETUS_ARGS+=("--reapermode=kill")
# set relatively high limits for ASF machines
# changing these to higher values may cause problems
# with other jobs on systemd-enabled machines
YETUS_ARGS+=("--dockermemlimit=20g")
# -1 spotbugs issues that show up prior to the patch being applied
YETUS_ARGS+=("--spotbugs-strict-precheck")
# rsync these files back into the archive dir
YETUS_ARGS+=("--archive-list=${ARCHIVE_PATTERN_LIST}")
# URL for user-side presentation in reports and such to our artifacts
YETUS_ARGS+=("--build-url-artifacts=${BUILD_URL_ARTIFACTS}")
# plugins to enable
YETUS_ARGS+=("--plugins=${PLUGINS}")
YETUS_ARGS+=("--tests-filter=test4tests")
# run in docker mode
YETUS_ARGS+=("--docker")
# our jenkins workers don't have buildkit installed (INFRA-24704)
YETUS_ARGS+=('--docker-buildkit=false')
# help keep the ASF boxes clean
YETUS_ARGS+=("--sentinel")
YETUS_ARGS+=("--github-token=${GITHUB_TOKEN}")
# use emoji vote so it is easier to find the broken line
YETUS_ARGS+=("--github-use-emoji-vote")
YETUS_ARGS+=("--github-repo=apache/hbase-kustomize")
# enable writing back to Github
YETUS_ARGS+=('--github-write-comment')
# increasing proc limit to avoid OOME: unable to create native threads
YETUS_ARGS+=("--proclimit=5000")


echo "Launching yetus with command line:"
echo "${TESTPATCHBIN} ${YETUS_ARGS[*]}"

/usr/bin/env bash "${TESTPATCHBIN}" "${YETUS_ARGS[@]}"
