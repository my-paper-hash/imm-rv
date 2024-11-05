#!/usr/bin/env python3

import os
import sys
from analyze_non_isolated_or_raw import need_to_exclude_specs

SCRIPT_DIR=os.path.dirname(os.path.realpath(__file__))


def main():
    if len(sys.argv) < 3 or not os.path.exists(sys.argv[1]) or not os.path.exists(sys.argv[2]):
        print('Usage: python3 handle_non_isolated.py <locator-log> <methods-list>')
        exit(1)

    methods = []
    with open(sys.argv[2]) as f:
        for line in f.readlines():
            line = line.strip()
            if line:
                methods.append(line.split(',')[0].split('#')[0])

    specs_to_exclude = {} # map specs to methods
    for method in methods:
        if '<clinit>' in method or '<init>' in method:
            # cannot handle them right now
            continue

        specs = need_to_exclude_specs(sys.argv[1], method)
        if specs is None:
            # nothing we can do to de-instrument this method
            continue
        for spec in specs:
            if spec in specs_to_exclude:
                specs_to_exclude[spec].append(method)
            else:
                specs_to_exclude[spec] = [method]

    # generate special BaseAspect to exclude methods
    generate_base_aspect(specs_to_exclude)


def generate_base_aspect(specs_to_exclude):
    base_aspect = ''
    with open(os.path.join(SCRIPT_DIR, '..', 'mop', 'BaseAspect_new.aj')) as f:
        base_aspect = f.read()

    os.makedirs(os.path.join(SCRIPT_DIR, '..', 'mop', 'mop'), exist_ok=True)
    for spec, methods in specs_to_exclude.items():
        spec_base_aspect = base_aspect.replace('BaseAspect', '{}BaseAspect'.format(spec))
        pointcuts = []
        for method in methods:
            method = method.split(':')[0]
            fqn = method.replace('$', '.')
            fq_path, _, method_name = fqn.rpartition('.')
            new_method = fq_path + '.' + 'IMM_' + method_name + '_*'
            pointcuts.append('withincode(* {}(..))'.format(new_method))
        
        if pointcuts:
                spec_base_aspect = spec_base_aspect.replace('!withincode(* *.IMM_*(..));', '(!withincode(* *.IMM_*(..)) || {});'.format(' || '.join(pointcuts)))

        print('Wrote spec base aspect for ' + spec)
        with open(os.path.join(SCRIPT_DIR, '..', 'mop', 'mop', '{}BaseAspect.aj'.format(spec)), 'w') as sf:
            sf.write(spec_base_aspect)


if __name__ == "__main__":
    main()
