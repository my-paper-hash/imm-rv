#!/bin/bash

PROJECT_DIR=$1
OUTPUT_PATH=$2

grep --include "*.java" -rhE "package [a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*;" ${PROJECT_DIR} | grep "^package" | cut -d ' ' -f 2 | sed 's/;.*//g' | sort -u > ${OUTPUT_PATH}
