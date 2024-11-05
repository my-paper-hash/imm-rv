#!/bin/bash
#
# (4) Run identified IMMs (evolution, 1 project)
# Usage: run_one.sh <project> <revisions-output> <classification-output> <output> <mode>
#
REPO=$1
REVISIONS_OUTPUT=$2
CLASSIFICATION_OUTPUT_DIR=$3
OUTPUT_DIR=$4
MODE=$5
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PROJECT_NAME=$(echo ${REPO} | tr / -)

function check_input() {
  if [[ ! -d ${REVISIONS_OUTPUT} || ! -d ${CLASSIFICATION_OUTPUT_DIR} || -z ${OUTPUT_DIR} || -z ${MODE} ]]; then
    echo "Usage: bash run_one.sh <project> <revisions-output> <classification-output> <output> <mode>"
    exit 1
  fi
  
  if [[ ${MODE} != "with" && ${MODE} != "without" ]]; then
    echo "mode: with (with update) or without (no update)"
    exit 1
  fi

  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
  fi

  mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}
}

function run_no_update() {
  local imm_list=""
  local imm_output=""
  local first_sha=""
  local gen_signature=true

  if [[ -f ${REVISIONS_OUTPUT}/logs/commits-check.txt ]]; then
    for SHA in $(grep "1,1,1$" ${REVISIONS_OUTPUT}/logs/commits-check.txt | cut -d ',' -f 1 | tac); do
      if [[ -n ${SHA} ]]; then
        if [[ ${imm_list} == "" || ${imm_output} == "" ]]; then
          if [[ ! -f ${CLASSIFICATION_OUTPUT_DIR}/mixed-imm-all/${SHA}.txt || ! -f ${CLASSIFICATION_OUTPUT_DIR}/output/${SHA}.txt ]]; then
            continue
          fi

          imm_list=${CLASSIFICATION_OUTPUT_DIR}/mixed-imm-all/${SHA}.txt
          imm_output=${CLASSIFICATION_OUTPUT_DIR}/output/${SHA}.txt
          first_sha=${SHA}
          echo "Use ${imm_list} and ${imm_output}"
        fi

        run_in_docker ${SHA} ${imm_list} ${imm_output} ${gen_signature}
        
        if [[ ${SHA} == ${first_sha} ]]; then
          if [[ -f ${OUTPUT_DIR}/${PROJECT_NAME}/${SHA}/output/logs/new-imm.txt ]]; then
            # each line in new imm_list will become "method:line#desc,categories"
            imm_list=${OUTPUT_DIR}/${PROJECT_NAME}/${SHA}/output/logs/new-imm.txt
            echo "Starting next SHA, use ${imm_list}"
            gen_signature=false
          fi
        fi
      fi
    done
  else
    echo "SKIP ${PROJECT_NAME}: cannot find commits-check.txt" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
  fi
}

function run_with_update() {
  local first_sha=""
  local gen_signature=true
  
  if [[ -f ${REVISIONS_OUTPUT}/logs/commits-check.txt ]]; then
    for SHA in $(grep "1,1,1$" ${REVISIONS_OUTPUT}/logs/commits-check.txt | cut -d ',' -f 1 | tac); do
      if [[ -n ${SHA} ]]; then
        if [[ ${first_sha} == "" ]]; then
          if [[ ! -f ${CLASSIFICATION_OUTPUT_DIR}/mixed-imm-all/${SHA}.txt || ! -f ${CLASSIFICATION_OUTPUT_DIR}/output/${SHA}.txt ]]; then
            continue
          fi
          first_sha=${SHA}
        fi
        
        imm_list=${CLASSIFICATION_OUTPUT_DIR}/mixed-imm-all/${SHA}.txt
        imm_output=${CLASSIFICATION_OUTPUT_DIR}/output/${SHA}.txt
        # Every SHA will use the latest classification results
        run_in_docker ${SHA} ${imm_list} ${imm_output} false
      fi
    done
  else
    echo "SKIP ${PROJECT_NAME}: cannot find commits-check.txt" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
  fi
}

function run_in_docker() {
  local SHA=$1
  local imm_list=$2
  local imm_output=$3
  local gen_signature=$4

  local start=$(date +%s%3N)
  echo "Running ${PROJECT_NAME} with SHA ${SHA}" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
  mkdir -p ${OUTPUT_DIR}/${PROJECT_NAME}/${SHA}

  local id=$(docker run -itd --name ${PROJECT_NAME}-${SHA} imm:latest)
  
  local attempt_num=1
  local success=false
  while [[ ${success} == false && ${attempt_num} -le 5 ]]; do
    docker exec -w /home/imm/imm-rv ${id} git pull
    if [[ $? -eq 0 ]]; then
      success=true
    else
      attempt_num=$((attempt_num + 1))
      echo "attempt ${attempt_num} failed - pull again in 60 seconds" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
      sleep 60
    fi
  done
  if [[ ${success} == false ]]; then
    log "Unable to pull after 5 attempts" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
    return 0
  fi

  
  docker cp ${imm_list} ${id}:/home/imm/imm.txt
  docker cp ${imm_output} ${id}:/home/imm/locator.log

  echo "Run command: timeout 21600s bash experiments/e2e/duplicate_methods.sh /home/imm/imm.txt ${REPO} ${SHA} /home/imm/output ${gen_signature}"
  docker exec -w /home/imm/imm-rv -e M2_HOME=/home/imm/apache-maven -e MAVEN_HOME=/home/imm/apache-maven -e CLASSPATH=/home/imm/aspectj-1.9.7/lib/aspectjtools.jar:/home/imm/aspectj-1.9.7/lib/aspectjrt.jar:/home/imm/aspectj-1.9.7/lib/aspectjweaver.jar: -e PATH=/home/imm/apache-maven/bin:/usr/lib/jvm/java-8-openjdk/bin:/home/imm/aspectj-1.9.7/bin:/home/imm/aspectj-1.9.7/lib/aspectjweaver.jar:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ${id} timeout 21600s bash experiments/e2e/duplicate_methods.sh /home/imm/imm.txt /home/imm/locator.log ${REPO} ${SHA} /home/imm/output ${gen_signature} &> ${OUTPUT_DIR}/${PROJECT_NAME}/${SHA}/docker.log

  docker cp ${id}:/home/imm/output ${OUTPUT_DIR}/${PROJECT_NAME}/${SHA}/output
  docker rm -f ${id}

  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "Finished running ${PROJECT_NAME} SHA ${SHA} in ${duration} ms" |& tee -a ${OUTPUT_DIR}/${PROJECT_NAME}/docker.log
}

check_input
if [[ ${MODE} == "without" ]]; then
  echo "Run without update"
  run_no_update
else
  echo "Run with update"
  run_with_update
fi
