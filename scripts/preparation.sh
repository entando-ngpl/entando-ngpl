#!/bin/bash

set -e

. "scripts/setup.sh"

step_01() {
  _log "==== Dump GitHub context ===="
  echo "$GITHUB_CONTEXT"
}

step_02() {
  _log "==== CHECKOUT ===="
  
  local CLONE_URL="$1";shift
  local REPO_FOLDER="$1";shift
  local BRANCH_NAME="$1";shift
  local TOKEN_SECRET="$1";shift
  CHECK_VARS --check-nn CLONE_URL TOKEN_SECRET REPO_FOLDER BRANCH_NAME
  
  _log "Remove label prepared (WORKOROUND TO ENSURE NEXT ADD LABEL EVENT IS TRIGGERED)"
  
  local authUrl=$(echo "$CLONE_URL" | sed "s|://|://$TOKEN_SECRET@|")
  
  git clone "$authUrl" "$REPO_FOLDER" || FATAL "Unable clone the repo \"$CLONE_URL\""
  
  cd "$REPO_FOLDER"
  git checkout "$BRANCH_NAME"|| FATAL "Unable checkout the brancg \"$BRANCH_NAME\""
  git pull
}

# PR FORMAT CHECK
step_03() {
  _log "==== PR NAME FORMAT CHECK ==== "

  local SHA="$1";shift
  local URL_TEMPLATE="$1";shift
  local PR_TITLE="$1";shift
  CHECK_VARS --check-nn SHA URL_TEMPLATE PR_TITLE
  
  local URL="${URL_TEMPLATE//\{sha\}/$SHA}"
  
  _log "Currently on COMMIT: $SHA"
  _log "Commit DATA: $URL | $PR_TITLE"
  
  # check name consistency
  if [ ! "$PR_TITLE" =~ ^[A-Z]{2,5}-[0-9]{1,5}([[:space:]]|:) ]; then
    echo "NOT MATCHING"
    GITHUB_UPDATE_JOB_STATUS "$GITHUB_UPDATE_URL" "failure" "Failed" "The Pull Request title does not respect the expected format. E.g. ENG-1234 feature description"
    exit 1
  fi

  # get PR story id
  PR_STORY_ID=$(echo "$PR_TITLE" | sed -E 's/([A-Z]{2,5}-[0-9]{1,5}).*/\1/')
  
  _log "PR_STORY_ID: $PR_STORY_ID"
  OPS_SET "PR_STORY_ID" "$PR_STORY_ID"
}

step_04() {
  _log "==== BOM CHECK ==== "

  local BOM_URL="$1";shift
  local REPO_FOLDER="$1";shift
  local LABELS="$1";shift
  CHECK_VARS --check-nn BOM_URL REPO_FOLDER --no-check LABELS

  #  SKIP?
  local SKIP_BOM_CHECK_LABEL=$(jq -r '.[] | select(.name=="no-bom-check")' <<< $LABELS)
  if [ -n "$SKIP_BOM_CHECK_LABEL" ]; then
    _log "Skipping BOM check due to skip label"
    exit 0
  fi
  
  # CHECK POM
  # check for pom.xml existence
  local FILE="$REPO_FOLDER/pom.xml"
  [[ -f "$FILE" ]] || {
    pwd;ls
    FATAL "Unable to find the project pom"
  }
  
  # fetch entando-core-bom tags
  local coreBomDir="entando-core-bom"
  mkdir "$coreBomDir" && cd "$coreBomDir"
  
  CMD_RETRY 35 30 -- git fetch --tag "$BOM_URL" &> /dev/null || FATAL "Unable to fetch the BOM tags"

  lastVersion=$(git describe --tags $(git rev-list --tags --max-count=1) | sed 's/^v\(.*\)/\1/')
  ASSERT_VAR_NN lastVersion
  
  cd .. && rm -rf "$coreBomDir"
  cd "$REPO_FOLDER"
  
  # Apply namespace and template..
  # -m: on every node matching this xpath
  # -v: get the "version" node value OR skip the error
  bomVersion=$(
    xmlstarlet sel -N pom="http://maven.apache.org/POM/4.0.0" -t \
    -m "/pom:project/pom:dependencyManagement/pom:dependencies/pom:dependency[pom:artifactId='entando-core-bom']" \
    -v "./pom:version" pom.xml
  ) || true

  # if the current project does not depends on entando-core-bom => exit OK
  ASSERT_VAR_NN bomVersion "BOM dependency not found"
  
  _log "BOM VERSION IN pom.xml: $bomVersion"
  _log "LAST_VERSION entando-core-bom AVAILABLE: $lastVersion"
  
  # if the pom.xml entando-core-bom version is not aligned with the last available one => exit FAIL
  if [[ "$bomVersion" != "$lastVersion" ]]; then
    OPS_UPDATE_JOB_STATUS "failure" "Failed" "The entando-core-bom version is not aligned with the latest available version"
    FATAL "BOM VERSION OUT OF DATE"
  fi
}
