#!/bin/bash
#
# (3) Identify IMMs
# Usage: classify.sh <project> <revisions-output> <traces-output> <classification-output> [threads=50]
#
REPO=$1
REVISIONS_OUTPUT=$2
TRACES_OUTPUT_DIR=$3
OUTPUT_DIR=$4
THREADS=${5:-50}
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PROJECT_NAME=$(echo ${REPO} | tr / -)

EXTENSION_DIR=${SCRIPT_DIR}/../../extensions
MOP_DIR=${SCRIPT_DIR}/../../mop

source ${SCRIPT_DIR}/../constants.sh
source ${SCRIPT_DIR}/../utils.sh

function check_input() {
  if [[ ! -d ${REVISIONS_OUTPUT} || ! -d ${TRACES_OUTPUT_DIR} || -z ${OUTPUT_DIR} ]]; then
    echo "Usage bash classify.sh <project> <revisions-output> <traces-output> <classification-output> [threads=50]"
    exit 1
  fi
  
  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
  fi

  mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}
}

function generate_mixed_imm_output() {
  local sha=$1
  rm -f ${OUTPUT_DIR}/${PROJECT_NAME}/mixed-imm-all/${sha}.txt;
  
  if [[ ! -f ${OUTPUT_DIR}/${PROJECT_NAME}/output/${sha}.txt || ! -f ${OUTPUT_DIR}/${PROJECT_NAME}/non-isolated-and-raw/${sha}.txt ]]; then
    return 1
  fi

  while read -r line; do
    if [[ -z ${line} ]]; then
      break;
    fi;
    method=$(echo ${line} | cut -d '(' -f 2 | cut -d ')' -f 1);
    non_isolated_raw_classification=$(awk -F, -v value="${method}" '$1 == value' ${OUTPUT_DIR}/${PROJECT_NAME}/non-isolated-and-raw/${sha}.txt);
    if [[ -z ${non_isolated_raw_classification} ]]; then
      echo "${method},$(echo ${line} | cut -d ' ' -f 3),ERROR";
    else
      classification=$(echo ${non_isolated_raw_classification} | cut -d ',' -f 2-);
      if [[ ${classification} == "UNSUPPORTED" || ${classification} == "ISOLATED_AND_NON_ISOLATED_SAME_SPEC" ]]; then
        continue;
      fi
      
      if [[ ${classification} == "ISOLATED_AND_NON_ISOLATED_DIFFERENT_SPEC" ]]; then
        if [[ -n $(echo "${method}" | grep "\$[[:digit:]]") ]]; then
          continue;
        fi
      fi
      echo "${method},$(echo ${line} | cut -d ' ' -f 3),${classification}" >> ${OUTPUT_DIR}/${PROJECT_NAME}/mixed-imm-all/${sha}.txt;
    fi
  done <<< $(cat ${OUTPUT_DIR}/${PROJECT_NAME}/output/${sha}.txt | grep "Classifier " | grep -E ",(ISOLATED_MULTIPLE_UNIQUE|ISOLATED_ONE_UNIQUE)" | grep -v "<init>" | grep -v "<clinit>");
  
  return 0
}

function run() {
  collected=false
  if [[ -f ${REVISIONS_OUTPUT}/logs/commits-check.txt ]]; then
    for SHA in $(grep "1,1,1$" ${REVISIONS_OUTPUT}/logs/commits-check.txt | cut -d ',' -f 1); do
      if [[ -n ${SHA} ]]; then
        mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}/output/
        mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}/non-isolated-and-raw/
        mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}/mixed-imm-all/

        echo "${SHA}: Generating initial classification"
        if [[ -d ${TRACES_OUTPUT_DIR}/${SHA}/all-traces ]]; then
          python3 ${SCRIPT_DIR}/../../scripts/imm_locator.py ${TRACES_OUTPUT_DIR}/${SHA}/all-traces @20000000 ${THREADS} &> ${OUTPUT_DIR}/${PROJECT_NAME}/output/${SHA}.txt
        else
          python3 ${SCRIPT_DIR}/../../scripts/imm_locator.py ${TRACES_OUTPUT_DIR}/${SHA} @20000000 ${THREADS} &> ${OUTPUT_DIR}/${PROJECT_NAME}/output/${SHA}.txt
        fi
        if [[ $? -ne 0 ]]; then
          echo "SKIP ${SHA} because imm_locator.py failed"
          continue
        fi
        
        echo "${SHA}: Generating isolated/non-isolated mixed classification"
        python3 ${SCRIPT_DIR}/../../scripts/analyze_non_isolated_or_raw.py ${OUTPUT_DIR}/${PROJECT_NAME}/output/${SHA}.txt > ${OUTPUT_DIR}/${PROJECT_NAME}/non-isolated-and-raw/${SHA}.txt
        if [[ $? -ne 0 ]]; then
          echo "SKIP ${SHA} because analyze_non_isolated_or_raw.py failed"
          continue
        fi
        
        echo "${SHA}: Generating mixed IMM output"
        generate_mixed_imm_output ${SHA}
        if [[ $? -ne 0 ]]; then
          echo "SKIP ${SHA} because generate_mixed_imm_output failed"
          continue
        fi
      fi
    done
  else
    echo "SKIP ${PROJECT_NAME}: cannot find commits-check.txt"
  fi
}

check_input
run
