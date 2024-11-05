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
        print('Usage: python3 imm_stability.py <revisions-output> <classification-output>')
        exit(1)
    
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
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

def check_imm_history(shas, classification_output):
    last_SHA_IMMs = set()
    for sha in shas:
        output_file = os.path.join(classification_output, 'mixed-imm-all', '{}.txt'.format(sha))
        if not os.path.exists(output_file):
            print('SKIP COMMIT {} because it does not have mixed-imm-all file')
            continue
    
        IMMs = get_all_imm(output_file)
        print('{},{},{}'.format(sha, len(IMMs.difference(last_SHA_IMMs)), len(last_SHA_IMMs.difference(IMMs))))
        

def get_all_imm(output_file):
    data = set()
    with open(output_file) as f:
        for line in f.readlines():
            line = line.strip()
            if line:
                data.add(line.split(',')[0])
    return data


if __name__ == "__main__":
    main()
    