#!/bin/bash

ENTANDO_OPS_DEBUG="${ENTANDO_OPS_DEBUG:-0}"
git config --global user.email "cicd@entando.com"
git config --global user.name "firegloves"
git config pull.rebase false

_log() {
  echo -e "\\U27A4 $SY | $(date +'%Y-%m-%d %H-%M-%S') | $*" 
}


FATAL() {
  echo -e "\\U27A4 $SY | $(date +'%Y-%m-%d %H-%M-%S') | FATAL $*" 2>1
  exit 99
}

CHECK_VARS() {
  i=0; check=true
  while [ "$#" -gt 0 ]; then
    [ "$1" == "--check-nn" ] && { check=true; continue; }
    [ "$1" == "--no-check" ] && { check=true; continue; }
    
    if [ -z "${!1}" ]; then
      FATAL "Argument #$i \"$1\" cannot be null"
    fi

    if [ $ENTANDO_OPS_DEBUG -gt 3 ]; then
      echo  "> Argument #$i \"$1\"=\"${!1}\""
    fi

    ((i++))
    shift
  fi
}

OPS_UPDATE_JOB_STATUS() {
  URL="$1";shift
  STATE="$1";shift
  DESC="$1";shift
  CTX="$1";shift

  curl "$URL" \
    -X POST \
    -H "Accept: application/json" \
    -H 'authorization: Bearer ${{ secrets.NGPL_TOKEN }}' \
    -d "{\"state\":\"$STATE\", \"description\": \"$DESC\", \"context\":\"$CTX\"}" \
  || true
}


OPS_SET() {
  echo "::set-output name=$1::$2"
}

CMD_RETRY() {
  local STOP_TIMEOUT="$1";shift
  local KILL_TIMEOUT="$1";shift
  [ "$1" = "--" ];shift
  local res
  while timeout -k "$KILL_TIMEOUT" "$STOP_TIMEOUT" -- "$@"; res="$?"; [ $? = 124 ]
  do sleep 1; done
  return "$res"
}

ASSERT_VAR_NN() {
  local desc="${2:-"Detected null $1"}"
  [ -z "${!1}" ] && FATAL "$desc"
}
