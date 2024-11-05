#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
pushd ${SCRIPT_DIR} &> /dev/null
mkdir -p mop
cp BaseAspect_new.aj mop/BaseAspect.aj
cp no-track-agent.jar no-track-agent-IMM.jar

ajc_args=""
zip_args=""

pushd mop &> /dev/null
for spec in $(ls ../props/ | grep ".mop" | cut -d '.' -f 1); do
  if [[ ! -f ${spec}BaseAspect.aj ]]; then
    # Generate BaseAspect for the spec if not exists
    cat BaseAspect.aj  | sed "s/BaseAspect/${spec}BaseAspect/" > ${spec}BaseAspect.aj
  fi

  ajc_args="${ajc_args} ${spec}BaseAspect.aj"
  zip_args="${zip_args} mop/${spec}BaseAspect.class"
done
ajc ${ajc_args}  # compile all .aj files, get .class
if [[ $? -ne 0 ]]; then
  exit 1
fi
popd &> /dev/null

zip no-track-agent-IMM.jar ${zip_args}  # add all the .class files to zip
rm -rf mop
popd &> /dev/null
