#!/bin/bash
#
# (2) Collect traces
# Usage: collect_traces.sh <project> <revisions-output> <traces-output> <tracemop-dir>
#
REPO=$1
REVISIONS_OUTPUT=$2
OUTPUT_DIR=$3
TRACEMOP_DIR=$4
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PROJECT_NAME=$(echo ${REPO} | tr / -)

EXTENSION_DIR=${SCRIPT_DIR}/../../extensions
MOP_DIR=${SCRIPT_DIR}/../../mop

source ${SCRIPT_DIR}/../constants.sh
source ${SCRIPT_DIR}/../utils.sh

function check_input() {
  if [[ ! -d ${REVISIONS_OUTPUT} || -z ${OUTPUT_DIR} || ! -d ${TRACEMOP_DIR} ]]; then
    echo "Usage bash collect_traces.sh <project> <revisions-output> <traces-output> <tracemop-dir>"
    exit 1
  fi
  
  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
  fi

  mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}
  mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}/logs/
}

function run() {
  collected=false
  if [[ -f ${REVISIONS_OUTPUT}/logs/commits-check.txt ]]; then
    for sha in $(grep "1,1,1$" ${REVISIONS_OUTPUT}/logs/commits-check.txt | cut -d ',' -f 1); do
      if [[ -n ${sha} ]]; then
          echo "Project ${PROJECT_NAME} collecting SHA ${sha}"
          bash ${TRACEMOP_DIR}/scripts/collect_traces.sh ${REPO} ${sha} ${OUTPUT_DIR}/${PROJECT_NAME}/${sha} &> ${OUTPUT_DIR}/${PROJECT_NAME}/logs/${sha}.log
          if [[ $? -ne 0 ]]; then
            echo "Failed to collect SHA first ${PROJECT_NAME} - ${sha}"
          fi
      fi
    done
  else
    echo "SKIP ${PROJECT_NAME}: cannot find commits-check.txt"
  fi
}

check_input
run
