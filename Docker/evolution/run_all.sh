#!/bin/bash
#
# (4) Run identified IMMs (evolution, multiple projects)
# Usage: run_all.sh <projects-list> <revisions-output> <classification-output> <output-dir> <mode>
#
SCRIPT_DIR=$(cd $(dirname $0) && pwd)

PROJECTS_LIST=$1
REVISIONS_DIR=$2
CLASSIFICATION_DIR=$3
OUTPUT_DIR=$4
MODE=$5
SCRIPT_DIR=$( cd $( dirname $0 ) && pwd )

function check_input() {
  if [[ ! -f ${PROJECTS_LIST} || ! -d ${REVISIONS_DIR} || ! -d ${CLASSIFICATION_DIR} || -z ${OUTPUT_DIR} || -z ${MODE} ]]; then
    echo "Usage: bash run_all.sh <projects-list> <revisions-output> <classification-output> <output-dir> <mode>"
    exit 1
  fi

  if [[ ${MODE} != "with" && ${MODE} != "without" ]]; then
    echo "mode: with (with update) or without (no update)"
    exit 1
  fi

  mkdir -p ${OUTPUT_DIR}
  
  if [[ ! -s ${PROJECTS_LIST} ]]; then
    echo "${PROJECTS_LIST} is empty..."
    exit 0
  fi
  
  if [[ -z $(grep "###" ${PROJECTS_LIST}) ]]; then
    echo "You must end your projects-list file with ###"
    exit 1
  fi
}

function run_project() {
  local repo=$1
  local project_name=$(echo ${repo} | tr / -)

  local start=$(date +%s%3N)
  echo "Running ${project_name}"
  
  if [[ ! -d ${REVISIONS_DIR}/${project_name} ]]; then
    echo "Missing ${REVISIONS_DIR}/${project_name}"
    sleep 180s
    return
  fi
  
  if [[ ! -d ${CLASSIFICATION_DIR}/${project_name} ]]; then
    echo "Missing ${CLASSIFICATION_DIR}/${project_name}"
    sleep 180s
    return
  fi
  
  bash ${SCRIPT_DIR}/run_one.sh ${repo} ${REVISIONS_DIR}/${project_name} ${CLASSIFICATION_DIR}/${project_name} ${OUTPUT_DIR} ${MODE}
  
  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "Finished running ${project_name} in ${duration} ms" |& tee -a docker_all.log
  sleep 60s # 1 minute cooldown
}

function run_all() {
  local start=$(date +%s%3N)
  while true; do
    if [[ ! -s ${PROJECTS_LIST} ]]; then
      echo "${PROJECTS_LIST} is empty..."
      exit 0
    fi

    local project=$(head -n 1 ${PROJECTS_LIST})
    if [[ ${project} == "###" ]]; then
      local end=$(date +%s%3N)
      local duration=$((end - start))
      echo "Finished running all projects in ${duration} ms" |& tee -a docker_all.log
      exit 0
    fi

    if [[ -z $(grep "###" ${PROJECTS_LIST}) ]]; then
      echo "You must end your projects-list file with ###"
      exit 1
    fi

    sed -i 1d ${PROJECTS_LIST}
    echo $project >> ${PROJECTS_LIST}
    run_project ${project} $@
  done

}

check_input
run_all $@
