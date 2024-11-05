#! /usr/bin/python3
#
# Count how many raw events and raw unique events
# Usage: python3 raw_events_counter.py <path-to-traces-dir>
#
import os
import re
import csv
import sys
import time
from utils import utils
from pathlib import Path


next_id = 0
TRACES_FILE_VERSION = 0


def run():
    number_of_raw_events, number_of_unique_raw_events, processed_raw_events = 0, 0, {}

    # Load unique traces and map into memory
    if os.path.isfile(os.path.join(traces_path, 'traces-id.txt')):
        return count_raw_events(traces_path, number_of_raw_events, number_of_unique_raw_events, processed_raw_events)
    else:
        if not os.path.exists(traces_path):
            print('Unable to find traces in path ' + traces_path)
            exit(1)

        # search all traces directory
        locations_map = {}
        for traces_dir in [d for d in os.listdir(traces_path) if os.path.isfile(os.path.join(traces_path, d, 'traces-id.txt'))]:
            traces_dir = os.path.join(traces_path, traces_dir)
            number_of_raw_events, number_of_unique_raw_events, processed_raw_events = count_raw_events(traces_dir, number_of_raw_events, number_of_unique_raw_events, processed_raw_events, locations_map)
        return number_of_raw_events, number_of_unique_raw_events, processed_raw_events


def get_traces_from_dir(dir):
    global TRACES_FILE_VERSION
    traces_id_file = os.path.join(dir, 'traces-id.txt')
    specs_frequency_file = os.path.join(dir, 'specs-frequency.csv')
    unique_traces_file = os.path.join(dir, 'unique-traces.txt')
    locations_file = os.path.join(dir, 'locations.txt')

    traces = []

    if os.path.isfile(traces_id_file) and os.path.isfile(specs_frequency_file) and os.path.isfile(locations_file):
        id_to_trace = {}
        i = 0
        if os.path.exists(unique_traces_file):
            with open(unique_traces_file) as f:
                line = f.readline().strip()
                if line == '=== UNIQUE TRACES WITH ID ===':
                    TRACES_FILE_VERSION = 1
                    
        raw_specs_traces_id = {} # map trace id to raw specs
        with open(specs_frequency_file) as f:
            for line in f.readlines():
                line = line.strip()
                if not line or line == 'OK':
                    continue
                
                id, _, spec_to_freq = line.partition(' ')
                if len(spec_to_freq) <= 2:
                    print('Error processing spec ID: {}'.format(id))
                    continue
                
                specs = set()
                spec_to_freq = spec_to_freq[1:-1]
                for spec_str in spec_to_freq.split(', '):
                    spec, freq = spec_str.split('=')
                    spec = spec[:-7]
                    
                    if utils.is_raw_spec(spec):
                        specs.add(spec)
                        
                if specs:
                    raw_specs_traces_id[id] = specs
                    
        with open(traces_id_file) as f:
            header = False
            for line in f.readlines():
                line = line.strip()
                if not header or not line:
                    header = True
                    continue
                match = re.match('^(\d+) \[(.*)\]$', line)
                if match and match.group(2):
                    # Non-empty events
                    id = match.group(1)
                    if id not in raw_specs_traces_id:
                        continue
                    
                    raw_specs_with_this_trace = raw_specs_traces_id[id]
                    
                    trace = match.group(2).split(', ')
                    
                    if TRACES_FILE_VERSION != 0:
                        # Convert new trace format, for example, turn [e1~2x3] into [e1~2, e1~2, e1~2]
                        new_trace = []
                        for event in trace:
                            event_name, _, location_id = event.partition('~')
                            if 'x' not in location_id:
                                new_trace.append(event)
                            else:
                                location_id, _, freq = location_id.partition('x')
                                event = '{}~{}'.format(event_name, location_id)
                                for j in range(int(freq)):
                                    new_trace.append(event)
                        trace = new_trace
                    traces.append((trace, raw_specs_with_this_trace, id))
    return traces


def count_raw_events(dir, number_of_raw_events, number_of_unique_raw_events, processed_raw_events, locations_map=None):
    for data in get_traces_from_dir(dir):
        trace = data[0]
        raw_specs_with_this_trace = data[1]

        # Rename event if locations_map is not None
        if locations_map is not None:
            trace = rename_events(trace, os.path.join(dir, 'locations.txt'), locations_map)

        for event in trace:
            if event not in processed_raw_events:
                # first time seeing this event (name + location id), all number of specs to unique raw events counter
                processed_raw_events[event] = set(raw_specs_with_this_trace)
                number_of_unique_raw_events += len(raw_specs_with_this_trace)
                number_of_raw_events += len(raw_specs_with_this_trace)
                # Uncomment the following line to see the unique event
                # print('({}) {}:{} - {}'.format(id, event, len(raw_specs_with_this_trace), raw_specs_with_this_trace))
            else:
                # some spec saw this event (name + location id) before
                for raw_spec in raw_specs_with_this_trace:
                    if raw_spec in processed_raw_events[event]:
                        # this raw spec saw the event before, add one to raw events counter
                        number_of_raw_events += 1
                    else:
                        # this spec sees the event for the first time, add one to unique raw events counter
                        processed_raw_events[event].add(raw_spec)
                        number_of_unique_raw_events += 1
                        number_of_raw_events += 1
                        # Uncomment the following line to see the unique event
                        # print('({}) {} - {}'.format(id, event, raw_spec))
    return number_of_raw_events, number_of_unique_raw_events, processed_raw_events


def rename_events(trace, locations_file, locations_map):
    global next_id
    location_id_to_line = {}

    with open(locations_file) as f:
        map_started = False
        for line in f.readlines():
            line = line.strip();
            if map_started:
                if line:
                    id, _, location = line.partition(' ')
                    location_id_to_line[id] = location
                else:
                    # Empty line means it is EOF
                    break
            elif line == '=== LOCATION MAP ===':
                map_started = True

    new_trace = []
    for event in trace:
        event_name, _, location_id = event.rpartition('~')
        event_long_location = location_id_to_line.get(location_id, '(Unknown)')
        if event_long_location in locations_map:
            # If long location is already in locations_map, get unique ID
            new_trace.append('{}~{}'.format(event_name, locations_map[event_long_location]))
        else:
            # Otherwise, add new long location to locations_map, set new unique ID
            locations_map[event_long_location] = next_id
            new_trace.append('{}~{}'.format(event_name, next_id))
            next_id += 1
    return new_trace


def main(argv=None):
    argv = argv or sys.argv
    
    if len(argv) < 2:
        print('Usage: python3 raw_events_counter.py <path-to-traces-dir>')
        exit(1)
 
    global traces_path, traces, location_id_to_line
    traces_path = argv[1]
    
    number_of_raw_events, number_of_unique_raw_events, processed_raw_events = run()
    
    raw_specs = set()
    for event, specs in processed_raw_events.items():
        raw_specs = raw_specs.union(specs)
    number_of_raw_specs = len(raw_specs)
    
    print('{} raw specs'.format(number_of_raw_specs))
    print('{} events from raw specs'.format(number_of_raw_events))
    print('{} unique events from raw specs'.format(number_of_unique_raw_events))
    print('{},{},{}'.format(number_of_raw_specs, number_of_raw_events, number_of_unique_raw_events))


if __name__ == '__main__':
    csv.field_size_limit(sys.maxsize)
    main()
    