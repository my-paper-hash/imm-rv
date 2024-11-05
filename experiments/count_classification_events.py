#!/usr/bin/env python3

import sys
import signal
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

with open(sys.argv[1]) as f:
    started = False
    events_in_method = 0
    for line in f.readlines():
        line = line.strip()
        if line:
            if line.startswith('Inspecting hot method'):
                started = True
            if started:
                if events_in_method == 0 and line.endswith('events are in hot method'):
                    events_in_method = int(line.split(' ')[1])
                if line.startswith('Classifier '):
                    classification = line.partition(',')[2]
                    print('{} {}'.format(events_in_method, classification))
                    events_in_method = 0
                    started = False
