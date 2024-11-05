#!/bin/bash
TIMEOUT="3600s"
SKIP="-Dcheckstyle.skip -Drat.skip -Denforcer.skip -Danimal.sniffer.skip -Dmaven.javadoc.skip -Dfindbugs.skip -Dwarbucks.skip -Dmodernizer.skip -Dimpsort.skip -Dpmd.skip -Dxjc.skip -Djacoco.skip -Dinvoker.skip -DskipDocs -DskipITs -Dmaven.plugin.skip -Dlombok.delombok.skip -Dlicense.skipUpdateLicense -Dremoteresources.skip"
TMP_DIR="/tmp/imm"
PROFILER=""
MEASURE_TEST_AND_MOP=true
