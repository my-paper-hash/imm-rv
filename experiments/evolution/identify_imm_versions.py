#!/usr/bin/env python3
import os
import re
import sys
import signal


dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(dir, '..', '..', 'scripts'))
from utils import utils


def main():
    if len(sys.argv) < 3 or not os.path.exists(sys.argv[1]) or not os.path.exists(sys.argv[2]):
        print('Usage: python3 identify_imm_versions.py <revisions-output> <classification-output>')
        exit(1)
    
    signal.signal(signal.SIGPIPE, signal.SIG_DFL) # so we can use python3 identify_imm_versions.py xx | head
    commits_check = os.path.join(sys.argv[1], 'logs', 'commits-check.txt')
    
    if not os.path.exists(commits_check):
        print('cannot find commits-check.txt file')
        exit(1)

    shas = get_shas(commits_check) # oldest SHA first
    check_imm_history(shas, sys.argv[2])
    

def get_shas(commits_check):
    shas = []
    with open(commits_check) as f:
        for l in f.readlines():
            l = l.strip()
            if l:
                if ',1,1,1' in l:
                    shas.append(l.split(',')[0])
    return reversed(shas)


def summarize_imm(data):
    pure_imm = 0
    mixed_imm = 0
    non_imm = 0
    for method, excluded_spec in data.items():
        if excluded_spec is None:
            non_imm += 1
        elif len(excluded_spec) > 0:
            mixed_imm += 1
        else:
            pure_imm += 1
    return pure_imm, mixed_imm, non_imm


def check_imm_history(shas, classification_output):
    # output/${SHA}.txt
    first_sha_data = None
    previous_sha_data = None
    number_of_sha = 0

    for sha in shas:
        output_file = os.path.join(classification_output, 'output', '{}.txt'.format(sha))
        if not os.path.exists(output_file):
            print('SKIP COMMIT {} because it does not have output file')
            continue
    
        data = generate_imm_data(output_file)
        if first_sha_data is None:
            pure_imm, mixed_imm, non_imm = summarize_imm(data)
            print('\tFirst SHA ({}) has {} pure, {} mixed, {} non-IMM'.format(sha, pure_imm, mixed_imm, non_imm))
            
#           if pure_imm + mixed_imm >= 10:
            first_sha_data = data
        else:
            number_of_sha += 1
            print('Checking IMMs after {} SHAs:'.format(number_of_sha))
            for method, excluded_specs in data.items():
                if method in first_sha_data:
                    # method exists in both first and current commits
                    if first_sha_data[method] is not None:
                        # method was an IMM (for first SHA)
                        if excluded_specs is None:
                            # method is not an IMM (for current SHA)
                            print('\t\t{} was IMM first SHA but is not IMM after {} SHAs'.format(method, number_of_sha))
                            continue
                        if len(excluded_specs.difference(first_sha_data[method])) > 0:
                            # method is an IMM, but current SHA excluded additional specs
                            print('\t\t{} was IMM first SHA with mixed specs, excluded specs changed after {} SHAs'.format(method, number_of_sha))
                            continue
            
            if previous_sha_data is not None:
                for method, excluded_specs in data.items():
                    if method in previous_sha_data:
                        # method exists in both previous and current commits
                        if previous_sha_data[method] is not None:
                            # method was an IMM (for previous SHA)
                            if excluded_specs is None:
                                # method is not an IMM (for current SHA)
                                print('\t\t{} was IMM last SHA, but is no longer an IMM'.format(method))
                                continue
                            if len(excluded_specs.difference(previous_sha_data[method])) > 0:
                                # method is an IMM, but current SHA excluded additional specs
                                print('\t\t{} was IMM last SHA with mixed specs, but excluded specs changed'.format(method))
                                continue
            
            pure_imm, mixed_imm, non_imm = summarize_imm(data)
            print('\t#{} SHA ({}) has {} pure, {} mixed, {} non-IMM'.format(number_of_sha, sha, pure_imm, mixed_imm, non_imm))
            previous_sha_data = data

def generate_imm_data(output_file):
    # map method to excluded specs, if no excluded spec, then it is isolated
    # if method maps to None, then method is not IMM
    data = {}
    with open(output_file) as f:
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
                
                if '<init>' in method or '<clinit>' in method or re.search('\$\d', method):
                    # init, clinit, or $# are not IMM
                    data[method] = None
                    continue

                categories = line.split(': ')[1].split(',')
                if 'ISOLATED_MULTIPLE_UNIQUE_NO_REDUNDANT' in categories or 'ISOLATED_SINGLE_TRACE' in categories:
                    # cannot handle, not IMM
                    data[method] = None
                    continue
                if 'ISOLATED_MULTIPLE_UNIQUE' not in categories and 'ISOLATED_ONE_UNIQUE' not in categories:
                    # not IMM
                    data[method] = None
                    continue

                raw_specs = set([spec for spec in isolated_specs if utils.is_raw_spec(spec)]) # all isolated raw
                isolated_specs = set([spec for spec in isolated_specs if not utils.is_raw_spec(spec)]) # all isolated non-raw
                
                if len(isolated_specs) == 0:
                    # No isolated trace, cannot de-instrument, not IMM
                    data[method] = None
                if len(non_isolated_spec) == 0:
                    # No non-isolated trace, we just need to exclude raw specs
                    data[method] = raw_specs
                if len(isolated_specs.intersection(non_isolated_spec)) > 0:
                    # Specs are mixed, some specs contain both isolated traces and non-isolated traces
                    data[method] = None
                else:
                    # Specs are seperated, if a spec contains isolated traces then it won't contain non-isolated traces and vice versa
                    data[method] = raw_specs.union(non_isolated_spec)
            elif start_isolated:
                isolated_specs.add(line.split(' ')[0])
            elif start_non_isolated:
                non_isolated_spec.add(line.split(' ')[0])
    return data


if __name__ == "__main__":
    main()
    