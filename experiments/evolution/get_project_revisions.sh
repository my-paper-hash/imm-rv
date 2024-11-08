#!/bin/bash
#
# (1) Select projects and SHAs for evaluation
# Usage: get_project_revisions.sh <revisions> <repo> <sha> <output-dir>
# Run compile, test, and RV
#
REVISIONS=$1
REPO=$2
SHA=$3
OUTPUT_DIR=$4
LOG_DIR=${OUTPUT_DIR}/logs
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PROJECT_NAME=$(echo ${REPO} | tr / -)

EXTENSION_DIR=${SCRIPT_DIR}/../../extensions
MOP_DIR=${SCRIPT_DIR}/../../mop

source ${SCRIPT_DIR}/../constants.sh
source ${SCRIPT_DIR}/../utils.sh

TMP_DIR=${TMP_DIR}-${PROJECT_NAME}

function check_input() {
  if [[ -z ${REVISIONS} || -z ${REPO} || -z ${SHA} || -z ${OUTPUT_DIR} ]]; then
    echo "Usage bash get_project_revisions.sh <revisions> <repo> <sha> <output-dir>"
    exit 1
  fi
  
  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
  fi

  mkdir -p ${OUTPUT_DIR}
  mkdir -p ${OUTPUT_DIR}/repo
  mkdir -p ${LOG_DIR}
}

function setup() {
  log "Setting up environment..."
  mvn -Dmaven.repo.local=${OUTPUT_DIR}/repo install:install-file -Dfile=${MOP_DIR}/no-track-agent.jar -DgroupId="javamop-agent" -DartifactId="javamop-agent" -Dversion="1.0" -Dpackaging="jar"
}

function log() {
  local message=$1
  echo "${message}" &>> ${LOG_DIR}/output.log
}

function test_commit() {
  local sha=$1
  mkdir -p ${LOG_DIR}/${sha}
  git checkout ${sha} &> /dev/null
  
  run_compile ${sha}
  if [[ $? -ne 0 ]]; then
    echo "${sha},0,0,0" >> ${LOG_DIR}/commits-check.txt
    
    log "Cannot use commit ${sha} due to compile error"
    return 1
  fi
  
  run_test ${sha}
  if [[ $? -ne 0 ]]; then
    echo "${sha},1,0,0" >> ${LOG_DIR}/commits-check.txt
    
    log "Cannot use commit ${sha} due to test error"
    return 1
  fi
  
  run_test_with_rv ${sha}
  if [[ $? -ne 0 ]]; then
    echo "${sha},1,1,0" >> ${LOG_DIR}/commits-check.txt
    
    log "Cannot use commit ${sha} due to rv error"
    return 1
  fi
  
  echo "${sha},1,1,1" >> ${LOG_DIR}/commits-check.txt
  log "Finished testing commit ${sha}"
  return 0
}

function run_compile() {
  local sha=$1
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  
  log "Running test-compile"
  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn -Djava.io.tmpdir=${TMP_DIR} -Dmaven.repo.local=${OUTPUT_DIR}/repo ${SKIP} clean test-compile) &>> ${LOG_DIR}/${sha}/compile.log
  local status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "[IMM] Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/${sha}/compile.log
  return ${status}
}

function run_test() {
  local sha=$1
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  
  log "Running test without MOP"
  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn -Djava.io.tmpdir=${TMP_DIR} -Dmaven.repo.local=${OUTPUT_DIR}/repo ${SKIP} surefire:test) &>> ${LOG_DIR}/${sha}/test.log
  local status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "[IMM] Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/${sha}/test.log
  
  return ${status}
}

function run_test_with_rv() {
  local sha=$1
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  
  log "Running test with MOP"
  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn -Djava.io.tmpdir=${TMP_DIR} -Dmaven.repo.local=${OUTPUT_DIR}/repo ${SKIP} surefire:test -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &>> ${LOG_DIR}/${sha}/mop.log
  local status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "[IMM] Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/${sha}/mop.log

  move_violations ${LOG_DIR}/${sha} violations  
  return ${status}
}

function get_project() {
  pushd ${OUTPUT_DIR} &> /dev/null
  
  export GIT_TERMINAL_PROMPT=0
  git clone https://github.com/${REPO} project &>> ${LOG_DIR}/clone.log
  pushd ${OUTPUT_DIR}/project &> /dev/null
  git checkout ${SHA} &>> ${LOG_DIR}/clone.log
  if [[ $? -ne 0 ]]; then
    log "Skip project: cannot clone repository"
    exit 1
  fi
  
  if [[ -f ${OUTPUT_DIR}/project/.gitmodules ]]; then
    log "Skip project: project contains submodule"
    exit 1
  fi
  
  local failure=0
  for commit in $(git rev-list --first-parent --topo-order --remove-empty --no-merges --branches=master -n 500 HEAD); do
    if [[ -z $(git show ${commit} --name-status | grep \\\.java) ]]; then
      # java files not changed
      continue
    fi
    
    if [[ ${commit} == ${SHA} ]]; then
      continue
    fi

    log "Testing commit ${commit}"
    test_commit ${commit}
    if [[ $? -ne 0 ]]; then
      failure=$((failure + 1))
      if [[ ${failure} -ge 10 ]]; then
        log "Skip project: 10 failures in a row"
        exit 1
      fi
    else
      failure=0
    fi
    
    local success=$(grep ,1,1,1 ${LOG_DIR}/commits-check.txt | wc -l)
    if [[ ${success} -ge ${REVISIONS} ]]; then
      break
    fi
    log "Found ${success} projects"
  done

  popd &> /dev/null
  popd &> /dev/null
  
  log "Done, found $(grep ,1,1,1 ${LOG_DIR}/commits-check.txt | wc -l)/$(cat ${LOG_DIR}/commits-check.txt | wc -l) valid commits"
}

export RVMLOGGINGLEVEL=UNIQUE
check_input
setup
get_project
