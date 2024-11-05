#!/bin/bash
#
# De-instrument IMM using duplicate methods strategy
# Usage: duplicate_methods.sh <path-to-classification> <path-to-imm-locator-log> <project-name> <sha> <output-dir> [gen-signature]
# <path-to-classification> should be a CSV file with the following format:
# method_name_1,<CUT/LIB>,category1,category2,category3,...
# method_name_2,<CUT/LIB>,category1,...
# ...
#
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PATH_TO_CLASSIFICATION=$1
PATH_TO_IMM_LOCATOR_LOG=$2
REPO=$3
PROJECT_NAME=$(echo ${REPO} | tr / -)
SHA=$4
OUTPUT_DIR=$5
GENERATE_SIGN=${6:-false}

source ${SCRIPT_DIR}/../constants.sh
source ${SCRIPT_DIR}/../utils.sh

TMP_DIR=${TMP_DIR}-${PROJECT_NAME}
EXTENSION_DIR=${SCRIPT_DIR}/../../extensions
MOP_DIR=${SCRIPT_DIR}/../../mop

export RVMLOGGINGLEVEL=UNIQUE
export MAVEN_OPTS="-Xmx500g -XX:-UseGCOverheadLimit"

function check_input() {
  if [[ ! -f ${PATH_TO_CLASSIFICATION} || ! -f ${PATH_TO_IMM_LOCATOR_LOG} || -z ${REPO} || -z ${SHA} || -z ${OUTPUT_DIR} ]]; then
    echo "Usage bash duplicate_methods.sh <path-to-classification> <path-to-imm-locator-log> <project-name> <sha> <output-dir> [gen-signature]"
    exit 1
  fi
  
  if [[ ! ${PATH_TO_CLASSIFICATION} =~ ^/.* ]]; then
    PATH_TO_CLASSIFICATION=${SCRIPT_DIR}/${PATH_TO_CLASSIFICATION}
  fi
  
  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
  fi
  
  if [[ ! ${PATH_TO_IMM_LOCATOR_LOG} =~ ^/.* ]]; then
    PATH_TO_IMM_LOCATOR_LOG=${SCRIPT_DIR}/${PATH_TO_IMM_LOCATOR_LOG}
  fi
  
  LOG_DIR=${OUTPUT_DIR}/logs
  mkdir -p ${LOG_DIR}
}

function setup() {
  pushd ${OUTPUT_DIR} &> /dev/null
  if [[ ! -d project ]]; then
    log "Cloning repository ${REPO}"
    
    # Clone
    local attempt_num=1
    local success=false
    while [[ ${success} == false && ${attempt_num} -le 5 ]]; do
      git clone https://github.com/${REPO} project
      if [[ $? -eq 0 ]]; then
        success=true
      else
        attempt_num=$((attempt_num + 1))
        echo "attempt ${attempt_num} failed - clone again in 60 seconds" |& tee -a ${LOG_DIR}/setup.log
        sleep 60
        rm -rf project
      fi
    done
    if [[ ${success} == false ]]; then
      log "Unable to clone after 5 attempts" |& tee -a ${LOG_DIR}/setup.log
      
      DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
      echo "EXIT 1 IN ${DURATION_TOTAL} ms"
      exit 1
    fi

    pushd project &> /dev/null
    git checkout ${SHA}
    bash ${SCRIPT_DIR}/../treat_special.sh ${OUTPUT_DIR}/project ${PROJECT_NAME}
    popd &> /dev/null
  fi

  pushd project &> /dev/null
  
  log "Downloading jar and compiling"
  export ADD_AGENT=0
  
  # Install JavaMOP agent
  local attempt_num=1
  local success=false
  while [[ ${success} == false && ${attempt_num} -le 5 ]]; do
    mvn -Dmaven.repo.local=${OUTPUT_DIR}/repo install:install-file -Dfile=${MOP_DIR}/no-track-agent.jar -DgroupId="javamop-agent" -DartifactId="javamop-agent" -Dversion="1.0" -Dpackaging="jar" &> ${LOG_DIR}/setup.log
    if [[ $? -eq 0 ]]; then
      success=true
    else
      attempt_num=$((attempt_num + 1))
      echo "attempt ${attempt_num} failed - install agent again in 60 seconds" |& tee -a ${LOG_DIR}/setup.log
      sleep 60
    fi
  done
  if [[ ${success} == false ]]; then
    log "Unable to install agent after 5 attempts" |& tee -a ${LOG_DIR}/setup.log
    
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  
  # Compile
  local attempt_num=1
  local success=false
  while [[ ${success} == false && ${attempt_num} -le 5 ]]; do
    (time mvn clean test-compile -Dmaven.repo.local=${OUTPUT_DIR}/repo -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &>> ${LOG_DIR}/setup.log
    if [[ $? -eq 0 ]]; then
      success=true
    else
      attempt_num=$((attempt_num + 1))
      echo "attempt ${attempt_num} failed - compile project again in 60 seconds" |& tee -a ${LOG_DIR}/setup.log
      sleep 60
    fi
  done
  if [[ ${success} == false ]]; then
    log "Unable to compile project after 5 attempts" |& tee -a ${LOG_DIR}/setup.log
    
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  
  # Test
  local attempt_num=1
  local success=false
  while [[ ${success} == false && ${attempt_num} -le 5 ]]; do
    mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
    (time mvn surefire:test -Djava.io.tmpdir=${TMP_DIR} -Dmaven.repo.local=${OUTPUT_DIR}/repo -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &>> ${LOG_DIR}/setup.log
    if [[ $? -eq 0 ]]; then
      success=true
    else
      attempt_num=$((attempt_num + 1))
      echo "attempt ${attempt_num} failed - test project again in 60 seconds" |& tee -a ${LOG_DIR}/setup.log
      sleep 60
    fi
  done
  if [[ ${success} == false ]]; then
    log "Unable to test project after 5 attempts" |& tee -a ${LOG_DIR}/setup.log
    
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi

  unset ADD_AGENT
  popd &> /dev/null
  popd &> /dev/null
  
  # Install deIMM
  pushd ${SCRIPT_DIR}/../duplicate_methods &> /dev/null
  local attempt_num=1
  local success=false
  while [[ ${success} == false && ${attempt_num} -le 10 ]]; do
    mvn package &>> ${LOG_DIR}/setup.log
    if [[ $? -eq 0 ]]; then
      success=true
    else
      attempt_num=$((attempt_num + 1))
      echo "attempt ${attempt_num} failed - duplicate_methods bytecode modifier again in 60 seconds" |& tee -a ${LOG_DIR}/setup.log
      sleep 60
    fi
  done
  if [[ ${success} == false ]]; then
    log "Unable to install duplicate_methods bytecode modifier after 10 attempts" |& tee -a ${LOG_DIR}/setup.log
    
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  popd  &> /dev/null
  
  echo "test status,test time,mop status,mop time,imm process status,imm process time,imm mop status,imm mop time" > ${LOG_DIR}/report.csv
}

function measure_regular_time() {
  pushd ${OUTPUT_DIR}/project &> /dev/null
  log "Measuring time without MOP"
  export ADD_AGENT=0
  
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn surefire:test -Djava.io.tmpdir=${TMP_DIR} ${SKIP} -Dmaven.repo.local=${OUTPUT_DIR}/repo -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &> ${LOG_DIR}/test.log
  status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  
  uptime >> ${LOG_DIR}/test.log
  log "Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/test.log
  echo -n "${status},${duration}" >> ${LOG_DIR}/report.csv
  if [[ ${status} -ne 0 ]]; then
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  unset ADD_AGENT
  
  
  log "Measuring time without using IMM"
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  if [[ -n ${PROFILER} ]]; then
    export MOP_AGENT_PATH="-javaagent:\${settings.localRepository}/javamop-agent/javamop-agent/1.0/javamop-agent-1.0.jar -agentpath:${PROFILER}=start,interval=5ms,event=wall,file=profile.jfr"
  fi

  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn surefire:test -Djava.io.tmpdir=${TMP_DIR} ${SKIP} -Dmaven.repo.local=${OUTPUT_DIR}/repo -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &> ${LOG_DIR}/mop.log
  status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  
  move_violations ${LOG_DIR}/violations mop_violations
  move_jfr ${LOG_DIR}/profiles mop_profile
  
  uptime >> ${LOG_DIR}/mop.log
  log "Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/mop.log
  echo -n ",${status},${duration}" >> ${LOG_DIR}/report.csv
  if [[ ${status} -ne 0 ]]; then
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  popd &> /dev/null
}

function process_imm() {
  log "Processing IMM"
  local jar_path="${SCRIPT_DIR}/../duplicate_methods/target/duplicate_methods-1.0-jar-with-dependencies.jar"
  if [[ ! -d ${SCRIPT_DIR}/duplicate_methods ]]; then
    mkdir ${SCRIPT_DIR}/duplicate_methods
    cp ${jar_path} ${SCRIPT_DIR}/duplicate_methods
    pushd ${SCRIPT_DIR}/duplicate_methods &> /dev/null
    jar -xf ${SCRIPT_DIR}/duplicate_methods/duplicate_methods-1.0-jar-with-dependencies.jar
    popd &> /dev/null
  fi
  
  if [[ ! -f ${OUTPUT_DIR}/classpath.txt ]]; then
    pushd ${OUTPUT_DIR}/project &> /dev/null
    timeout ${TIMEOUT} mvn -Dmaven.repo.local=${OUTPUT_DIR}/repo dependency:build-classpath -Dmdep.outputFile=/dev/stdout -q 2>&1 | cat > ${OUTPUT_DIR}/classpath.txt
    popd &> /dev/null
  fi
  local cp="${SCRIPT_DIR}/duplicate_methods:${OUTPUT_DIR}/project/target/classes:${OUTPUT_DIR}/project/target/test-classes:$(cat ${OUTPUT_DIR}/classpath.txt)"

  local start=$(date +%s%3N)
  while read -r line; do
    echo "Processing IMM ${line}" &>> ${LOG_DIR}/process.log
    local method=$(echo "${line}" | cut -d ',' -f 1)
    local categories=$(echo "${line}" | cut -d ',' -f 2-)
    local cut_or_lib=$(echo "${line}" | cut -d ',' -f 2)
    
    local class_name=$(echo "${method}" | rev | cut -d '.' -f 2- | rev | tr '.' '/')
    local method_name=$(echo "${method}" | rev | cut -d '.' -f 1 | rev)
  
    # class is not in a package, verify CUT or LIB again
    pushd ${OUTPUT_DIR}/project &> /dev/null
    if [[ -f target/classes/${class_name}.class || -f target/test-classes/${class_name}.class ]]; then
      echo "Classifier mis-identified ${class_name}, this class is in CUT"
      cut_or_lib="CUT"
    fi
    popd &> /dev/null

    if [[ ${cut_or_lib} == "CUT" ]]; then
      pushd ${OUTPUT_DIR}/project &> /dev/null
      local original_bytecode=""
      if [[ -f target/classes/${class_name}.class ]]; then
        original_bytecode="${OUTPUT_DIR}/project/target/classes/${class_name}.class"
      elif [[ -f target/test-classes/${class_name}.class ]]; then
        original_bytecode="${OUTPUT_DIR}/project/target/test-classes/${class_name}.class"
      fi
      
      if [[ -z ${original_bytecode} ]]; then
        log "Unable to de-instrument ${method} because it cannot find the bytecode file" |& tee -a ${LOG_DIR}/process.log
        continue
      fi
      
      echo "Changing bytecode using command: java -cp ${cp} org.imm.IMMTransformer ${original_bytecode} replace ${method_name}" &>> ${LOG_DIR}/process.log
      (java -cp ${cp} org.imm.IMMTransformer ${original_bytecode} replace ${method_name}) &>> ${LOG_DIR}/process.log
      local status=$?
      if [[ ${status} -ne 0 ]]; then
        log "ERROR: Unable to de-instrument method ${method} due to an error (exit code: ${status})" |& tee -a ${LOG_DIR}/process.log
      elif [[ ${GENERATE_SIGN} == true ]]; then
        echo "${method}#$(tail -n 1 ${LOG_DIR}/process.log),${categories}" &>> ${LOG_DIR}/new-imm.txt
      fi
      popd &> /dev/null
    else
      log "Changing bytecode using command: java -cp ${cp} org.imm.IMMTransformer ${class_name} replace ${method_name} ${OUTPUT_DIR}/classpath.txt" &>> ${LOG_DIR}/process.log
      (java -cp ${cp} org.imm.IMMTransformer ${class_name} replace ${method_name} ${OUTPUT_DIR}/classpath.txt) &>> ${LOG_DIR}/process.log
      local status=$?
      if [[ ${status} -ne 0 ]]; then
        log "ERROR: Unable to de-instrument method ${method} due to an error (exit code: ${status})" |& tee -a ${LOG_DIR}/process.log
      elif [[ ${GENERATE_SIGN} == true ]]; then
        echo "${method}#$(tail -n 1 ${LOG_DIR}/process.log),${categories}" &>> ${LOG_DIR}/new-imm.txt
      fi
    fi
  done < ${PATH_TO_CLASSIFICATION}
  
  if [[ ! -f ${MOP_DIR}/no-track-agent-IMM.jar ]]; then
    echo "Preping BaseAspect"  &>> ${LOG_DIR}/process.log
    (time python3 ${SCRIPT_DIR}/../../scripts/handle_non_isolated.py ${PATH_TO_IMM_LOCATOR_LOG} ${PATH_TO_CLASSIFICATION}) &>> ${LOG_DIR}/process.log
    if [[ $? -ne 0 ]]; then
      log "Unable to create BaseAspect" |& tee -a ${LOG_DIR}/process.log
      
      DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
      echo "EXIT 1 IN ${DURATION_TOTAL} ms"
      exit 1
    fi

    echo "Building agent" &>> ${LOG_DIR}/process.log
    (time bash ${MOP_DIR}/build.sh) &>> ${LOG_DIR}/process.log
    if [[ $? -ne 0 ]]; then
      log "Unable to build agent" |& tee -a ${LOG_DIR}/process.log
      
      DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
      echo "EXIT 1 IN ${DURATION_TOTAL} ms"
      exit 1
    fi
  fi
  (time mvn -Dmaven.repo.local=${OUTPUT_DIR}/repo install:install-file -Dfile=${MOP_DIR}/no-track-agent-IMM.jar -DgroupId="javamop-agent" -DartifactId="javamop-agent" -Dversion="1.0" -Dpackaging="jar") &>> ${LOG_DIR}/process.log
  if [[ $? -ne 0 ]]; then
    log "Unable to install IMM JavaMOP agent" |& tee -a ${LOG_DIR}/process.log
    
    DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
    echo "EXIT 1 IN ${DURATION_TOTAL} ms"
    exit 1
  fi
  
  local end=$(date +%s%3N)
  local duration=$((end - start))
  
  uptime >> ${LOG_DIR}/test.log
  log "Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/process.log
  echo -n ",${status},${duration}" >> ${LOG_DIR}/report.csv
}

function measure_imm_time() {
  pushd ${OUTPUT_DIR}/project &> /dev/null
  log "Measuring time using IMM"
  mkdir -p ${TMP_DIR} && chmod -R +w ${TMP_DIR} && rm -rf ${TMP_DIR} && mkdir -p ${TMP_DIR}
  local start=$(date +%s%3N)
  (time timeout ${TIMEOUT} mvn surefire:test -Djava.io.tmpdir=${TMP_DIR} ${SKIP} -Dmaven.repo.local=${OUTPUT_DIR}/repo -Dmaven.ext.class.path=${EXTENSION_DIR}/javamop-extension-1.0.jar) &> ${LOG_DIR}/imm.log
  status=$?
  local end=$(date +%s%3N)
  local duration=$((end - start))
  
  move_violations ${LOG_DIR}/violations imm_violations
  move_jfr ${LOG_DIR}/profiles imm_profile

  uptime >> ${LOG_DIR}/imm.log
  log "Duration: ${duration} ms, status: ${status}" |& tee -a ${LOG_DIR}/imm.log
  echo ",${status},${duration}" >> ${LOG_DIR}/report.csv
  popd &> /dev/null
}

function get_method_counter() {
  echo "Counting method calls frequency"
  pushd ${SCRIPT_DIR}/../method_call_counter &> /dev/null
  bash test.sh ${REPO} ${SHA} ${OUTPUT_DIR}/project ${OUTPUT_DIR}/repo &> ${LOG_DIR}/counter.log
  popd &> /dev/null
}

START_TIME=$(date +%s%3N)

check_input
setup
if [[ ${MEASURE_TEST_AND_MOP} == "true" ]]; then
  measure_regular_time
fi
process_imm
measure_imm_time
#get_method_counter

DURATION_TOTAL=$(($(date +%s%3N) - $START_TIME))
echo "EXIT 0 IN ${DURATION_TOTAL} ms"
