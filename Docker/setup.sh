#!/bin/bash

SCRIPT_DIR=$( cd $( dirname $0 ) && pwd )
IMM_DIR="${SCRIPT_DIR}/imm-rv"

function clone_repository() {
  echo "Cloning imm repository"
  pushd ${SCRIPT_DIR}
  git clone https://github.com/my-paper-hash/imm-artifact imm-rv
  popd
}

function build_extension() {
  echo "Building javamop extension"
  pushd ${IMM_DIR}/extensions/javamop-extension
  mvn package
  cp target/javamop-extension-1.0.jar ${IMM_DIR}/extensions/
  popd
}

function build_agents() {
  echo "Building agents"
  pushd ${IMM_DIR}/mop
  bash build.sh
  popd
}

function setup() {
  clone_repository
  build_extension
  build_agents
}

setup
