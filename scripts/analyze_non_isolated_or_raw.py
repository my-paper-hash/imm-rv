#!/usr/bin/env python3

import os
import sys
import signal
from utils import utils


def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        print('Usage: python3 analyze_non_isolated_or_raw.py <locator-log>')
        exit(1)
    
    signal.signal(signal.SIGPIPE, signal.SIG_DFL) # so we can use python3 analyze_non_isolated.py xx | head
    get_methods_info(sys.argv[1])


def get_methods_info(file_path):
    with open(file_path) as f:
        method = ''
        isolated_specs = set()
        non_isolated_spec = set()
        start_isolated = False
        start_non_isolated = False
        
        for line in f.readlines():
            line = line.strip()
            if line.startswith('Inspecting hot method'):
                method = line.split(' ')[3][:-3]
                isolated_specs = set()
                non_isolated_spec = set()
                start_isolated = False
                start_non_isolated = False
            elif line.startswith('Specs that have isolated traces'):
                start_isolated = True
                start_non_isolated = False
            elif line.startswith('Specs that have non-isolated traces'):
                start_isolated = False
                start_non_isolated = True
            elif line.startswith('Classifier '):
                start_isolated = False
                start_non_isolated = False

                categories = line.split(': ')[1].split(',')
                if 'ISOLATED_MULTIPLE_UNIQUE_NO_REDUNDANT' in categories or 'ISOLATED_SINGLE_TRACE' in categories:
                    # cannot handle
                    print('{},UNSUPPORTED'.format(method))
                    continue

                isolated_specs = set([spec for spec in isolated_specs if not utils.is_raw_spec(spec)])
                
                if len(isolated_specs) == 0:
                    # nothing we can do
                    print('{},NO_ISOLATED'.format(method))
                elif len(non_isolated_spec) == 0:
                    # can already handle
                    print('{},NO_NON_ISOLATED'.format(method))
                elif len(isolated_specs.intersection(non_isolated_spec)) > 0:
                    # cannot handle
                    print('{},ISOLATED_AND_NON_ISOLATED_SAME_SPEC'.format(method))
                else:
                    # can handle
                    print('{},ISOLATED_AND_NON_ISOLATED_DIFFERENT_SPEC'.format(method))
            elif start_isolated:
                isolated_specs.add(line.split(' ')[0])
            elif start_non_isolated:
                non_isolated_spec.add(line.split(' ')[0])


def need_to_exclude_specs(file_path, input_method):
    # List of specs we need to exclude from de-instrumentation
    # None if we shouldn't de-instrument the method
    with open(file_path) as f:
        isolated_specs = set()
        non_isolated_spec = set()
        start_isolated = False
        start_non_isolated = False
        checking = False
    
        for line in f.readlines():
            line = line.strip()
            if line.startswith('Inspecting hot method'):
                method = line.split(' ')[3][:-3]
                if input_method != None and input_method != method:
                    # current method is not the target method, then skip
                    checking = False
                    continue
                checking = True
            elif checking:
                if line.startswith('Specs that have isolated traces'):
                    start_isolated = True
                    start_non_isolated = False
                elif line.startswith('Specs that have non-isolated traces'):
                    start_isolated = False
                    start_non_isolated = True
                elif line.startswith('Classifier '):
                    categories = line.split(': ')[1].split(',')
                    if 'ISOLATED_MULTIPLE_UNIQUE_NO_REDUNDANT' in categories or 'ISOLATED_SINGLE_TRACE' in categories:
                        # Isolated traces are not pure, cannot de-instrument
                        return None

                    raw_specs = [spec for spec in isolated_specs if utils.is_raw_spec(spec)] # all isolated raw
                    isolated_specs = set([spec for spec in isolated_specs if not utils.is_raw_spec(spec)]) # all isolated non-raw

                    if len(isolated_specs) == 0:
                        # No isolated trace, cannot de-instrument
                        return None
                    if len(non_isolated_spec) == 0:
                        # No non-isolated trace, we just need to exclude raw specs
                        return raw_specs
                    if len(isolated_specs.intersection(non_isolated_spec)) > 0:
                        # Specs are mixed, some specs contain both isolated traces and non-isolated traces
                        return None
                    else:
                        # Specs are seperated, if a spec contains isolated traces then it won't contain non-isolated traces and vice versa
                        return sorted(raw_specs + list(non_isolated_spec))
                elif start_isolated:
                    isolated_specs.add(line.split(' ')[0])
                elif start_non_isolated:
                    non_isolated_spec.add(line.split(' ')[0])
    return None

if __name__ == "__main__":
    main()
