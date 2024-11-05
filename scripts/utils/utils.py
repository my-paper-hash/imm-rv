#!/usr/bin/env python3
import os
import subprocess
from utils.specs import raw_specs


def is_raw_spec(spec):
    return spec in raw_specs


def is_in_CUT(method, traces_dir):
    # project dir is the parent of traces_dir
    project_dir = os.path.join(traces_dir, '..')
    packages_path = os.path.join(project_dir, 'packages.txt')
    if not os.path.exists(os.path.join(project_dir, 'packages.txt')):
        script_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'find_packages.sh')
        subprocess.run('bash {} {} {}'.format(script_path, project_dir, packages_path), shell=True)
    package_name = '.'.join(method.split('.')[:-2])
    with open(packages_path) as f:
        for line in f.readlines():
            line = line.strip()
            if line.lower() == package_name.lower():
                return True
    return False
