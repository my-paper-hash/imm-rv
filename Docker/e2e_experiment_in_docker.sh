#!/bin/bash
#
# Run e2e experiment in Docker
# Before running this script, run `docker login`
# Usage: e2e_experiment_in_docker.sh <projects-list> <imm-dir> <locator-dir> <output-dir> [branch=false] [timeout=86400s] [test-timeout=1800s] [-p false] [-t true]
# imm directory must contains file: <project-name>.txt
# -p enable profiling
#
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
PROFILER=""
TIMED=""
REPO_DIR=""
PROJECT_DIR=""

while getopts :p:t:r:c: opts; do
  case "${opts}" in
    p ) PROFILER="${OPTARG}" ;;
    t ) TIMED="${OPTARG}" ;;
    r ) REPO_DIR="${OPTARG}" ;;
    c ) PROJECT_DIR="${OPTARG}" ;;
  esac
done
shift $((${OPTIND} - 1))

PROJECTS_LIST=$1
IMM_DIR=$2
LOCATOR_DIR=$3
OUTPUT_DIR=$4
BRANCH=$5
TIMEOUT=$6
TEST_TIMEOUT=$7

function check_input() {
  if [[ ! -d ${IMM_DIR} || ! -d ${LOCATOR_DIR} || ! -f ${PROJECTS_LIST} || -z ${OUTPUT_DIR} ]]; then
    echo "Usage: e2e_experiment_in_docker.sh <projects-list> <imm-dir> <locator-dir> <output-dir> [branch=false] [timeout=86400s] [test-timeout=1800s]"
    exit 1
  fi

  if [[ ! ${IMM_DIR} =~ ^/.* ]]; then
    IMM_DIR=${SCRIPT_DIR}/${IMM_DIR}
  fi

  if [[ ! ${OUTPUT_DIR} =~ ^/.* ]]; then
    OUTPUT_DIR=${SCRIPT_DIR}/${OUTPUT_DIR}
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

  if [[ -z ${TIMEOUT} ]]; then
    TIMEOUT=86400s
  fi
}


function run_project() {
  local repo=$1

  sha=$(echo "${repo}" | cut -d ',' -f 2)
  repo=$(echo "${repo}" | cut -d ',' -f 1)

  local project_name=$(echo ${repo} | tr / -)

  if [[ ! -f ${IMM_DIR}/${project_name}.txt ]]; then
    echo "Skip ${project_name} because its imm list is not in imm-directory"
    return
  fi
  
  if [[ ! -f ${LOCATOR_DIR}/${project_name}.txt ]]; then
    echo "Skip ${project_name} because its locator log is not in locator directory"
    return
  fi

  local start=$(date +%s%3N)
  echo "Running ${project_name} with SHA ${sha}"
  mkdir -p ${OUTPUT_DIR}/${project_name}

  local id=$(docker run -itd --name ${project_name} imm:latest)
  docker exec -w /home/imm/imm-rv ${id} git pull
  if [[ $? -ne 0 ]]; then
    echo "Unable to pull project ${project_name}, try again in 60 seconds" |& tee -a docker.log
    sleep 60
    docker exec -w /home/imm/imm-rv ${id} git pull
    if [[ $? -ne 0 ]]; then
      echo "Skip ${project_name} because script can't pull" |& tee -a docker.log
      return
    fi
  fi
  
  if [[ -n ${BRANCH} && ${BRANCH} != "false" ]]; then
    docker exec -w /home/imm/imm-rv ${id} git checkout ${BRANCH}
    docker exec -w /home/imm/imm-rv ${id} git pull
  fi
  
  if [[ -n ${REPO_DIR} && -d ${REPO_DIR}/${project_name} ]]; then
    echo "Found m2 repo, copying to container..."
    docker exec ${id} mkdir -p /home/imm/output
    if [[ ! -f ${REPO_DIR}/${project_name}.tar.gz ]]; then
      pushd ${REPO_DIR} &> /dev/null
      tar czf ${project_name}.tar.gz ${project_name} &> /dev/null
      popd &> /dev/null
    fi
    docker cp ${REPO_DIR}/${project_name}.tar.gz ${id}:/home/imm/output/repo.tar.gz
    docker exec -w /home/imm/output ${id} tar xzf repo.tar.gz
    docker exec ${id} rm -rf /home/imm/output/repo.tar.gz
    docker exec ${id} mv /home/imm/output/${project_name} /home/imm/output/repo
  fi
  
  if [[ -n ${PROJECT_DIR} && -d ${PROJECT_DIR}/${project_name} ]]; then
    echo "Found project dir, copying to container..."
    docker exec ${id} mkdir -p /home/imm/output
    if [[ ! -f ${PROJECT_DIR}/${project_name}.tar.gz ]]; then
      pushd ${PROJECT_DIR} &> /dev/null
      tar czf ${project_name}.tar.gz ${project_name} &> /dev/null
      popd &> /dev/null
    fi
    docker cp ${PROJECT_DIR}/${project_name}.tar.gz ${id}:/home/imm/output/project.tar.gz
    docker exec -w /home/imm/output ${id} tar xzf project.tar.gz
    docker exec ${id} rm -rf /home/imm/output/project.tar.gz
    docker exec ${id} mv /home/imm/output/${project_name} /home/imm/output/project
  fi

  if [[ -n ${TEST_TIMEOUT} ]]; then
    echo "Setting test timeout to ${TEST_TIMEOUT}"
    docker exec -w /home/imm/imm-rv ${id} sed -i "s/TIMEOUT=.*/TIMEOUT=${TEST_TIMEOUT}/" experiments/constants.sh
  fi
  
  if [[ ${PROFILER} == "true" ]]; then
    echo "Setting profiler path to ${PROFILER}"
    docker exec -w /home/imm/imm-rv ${id} sed -i "s/PROFILER=.*/PROFILER=\"\/home\/imm\/async-profiler-2.9-linux-x64\/build\/libasyncProfiler.so\"/" experiments/constants.sh
  fi
  
  if [[ ${TIMED} == "false" ]]; then
    echo "Setting measure test/mop time to ${TIMED}"
    docker exec -w /home/imm/imm-rv ${id} sed -i "s/MEASURE_TEST_AND_MOP=.*/MEASURE_TEST_AND_MOP=${TIMED}/" experiments/constants.sh
  fi

  docker cp ${IMM_DIR}/${project_name}.txt ${id}:/home/imm/imm.txt
  docker cp ${LOCATOR_DIR}/${project_name}.txt ${id}:/home/imm/locator.log
  
  echo "Run command: timeout ${TIMEOUT} bash experiments/e2e/duplicate_methods.sh /home/imm/imm.txt ${repo} ${sha} /home/imm/output"
  timeout ${TIMEOUT} docker exec -w /home/imm/imm-rv -e M2_HOME=/home/imm/apache-maven -e MAVEN_HOME=/home/imm/apache-maven -e CLASSPATH=/home/imm/aspectj-1.9.7/lib/aspectjtools.jar:/home/imm/aspectj-1.9.7/lib/aspectjrt.jar:/home/imm/aspectj-1.9.7/lib/aspectjweaver.jar: -e PATH=/home/imm/apache-maven/bin:/usr/lib/jvm/java-8-openjdk/bin:/home/imm/aspectj-1.9.7/bin:/home/imm/aspectj-1.9.7/lib/aspectjweaver.jar:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ${id} timeout ${TIMEOUT} bash experiments/e2e/duplicate_methods.sh /home/imm/imm.txt /home/imm/locator.log ${repo} ${sha} /home/imm/output &> ${OUTPUT_DIR}/${project_name}/docker.log

  docker cp ${id}:/home/imm/output ${OUTPUT_DIR}/${project_name}/output

  docker rm -f ${id}
  
  local end=$(date +%s%3N)
  local duration=$((end - start))
  echo "Finished running ${project_name} in ${duration} ms" |& tee -a docker.log
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
      echo "Finished running all projects in ${duration} ms" |& tee -a docker.log

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
