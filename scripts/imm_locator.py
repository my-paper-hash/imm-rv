#! /usr/bin/python3
#
# Find IMM
# Usage: python3 imm_locator.py <path-to-traces-dir> [inspect-method] [number-of-threads]
# If inspect-method is not given, then the script will find all hot methods in path-to-traces-dir
# If it is given, then the script will output the stats of the given hot method
# If inspect-method starts from @x (e.g., @1, @2, @10), then will it get the top x methods
# It includes # of events and traces in hot method,
# number of related traces in that test (at least 1 event in the trace is in hot method),
# and number of isolated related traces in that test (all events in the trace are in hot method).
#
import os
import re
import csv
import sys
import time
from utils import utils
import classifier
from pathlib import Path
from collections import defaultdict
import multiprocessing


THREADS_MAX = 25
traces_path = ''
next_spec_id = 0
spec_to_id = {} # map spec to ID
id_to_spec = {} # map id to spec
raw_specs_id = set()
TRACES_FILE_VERSION = 0

traces, location_id_to_line, traces_to_related_methods, method_to_related_id = {}, {}, [], {}


def get_all_traces():
    # Load unique traces and map into memory
    if os.path.isfile(os.path.join(traces_path, 'unique-traces.txt')):
        traces_lines, map_lines = get_traces_from_dir(traces_path)
        return traces_lines, map_lines
    else:
        # search all traces directory
        all_traces_lines = {} # map {trace: {spec_id: frequency}}
        all_map_lines = {} # map {short ID: long location}
        global_location = {} # map {long location: global short ID}
        next_id = 0
        for traces_dir in [d for d in os.listdir(traces_path) if os.path.isfile(os.path.join(traces_path, d, 'unique-traces.txt'))]:
            traces_dir = os.path.join(traces_path, traces_dir)
            print('Reading traces from ' + traces_dir)

            # traces_lines is [(events (list), frequency (int), spec_id (str)]
            # map_lines is {short ID (str): long location (str)}
            traces_lines, map_lines = get_traces_from_dir(traces_dir)
            for trace in traces_lines:
                events, frequency, spec_id = trace
                new_events = []
                for event in events:
                    event_name, _, location_id = event.rpartition('~')
                    event_freq = None
                    # FIX: Don't think this is needed, get_traces_from_dir will already expand the traces
                    if TRACES_FILE_VERSION == 1:
                        event_name, _, location_id = event.rpartition('~')
                        if 'x' in location_id:
                            location_id, _, event_freq = location_id.partition('x')
                    # translate location_id to global location_id
                    long_location = map_lines.get(location_id, '(Unknown)')
                    if long_location in global_location:
                        global_short_location = global_location[long_location]
                    else:
                        next_id += 1
                        global_short_location = str(next_id)
                        global_location[long_location] = global_short_location
                        all_map_lines[global_short_location] = long_location
                    # converted event:
                    new_events.append('{}~{}x{}'.format(event_name, global_short_location, event_freq) if event_freq else '{}~{}'.format(event_name, global_short_location))
                # now that we have a new converted trace (new_events), we have to track its frequency
                converted_trace = ', '.join(new_events)
                if converted_trace in all_traces_lines:
                    all_traces_lines[converted_trace][spec_id] = all_traces_lines[converted_trace].get(spec_id, 0) + frequency
                else:
                    all_traces_lines[converted_trace] = {spec_id: frequency}
        # convert all_traces_lines to [(events (list), frequency (int), spec_id (str)]
        print('Converting set of traces...')
        output = []
        for trace, spec_and_freq in all_traces_lines.items():
            trace = trace.split(', ')
            for spec, freq in spec_and_freq.items():
                output.append((trace, freq, spec))
        return output, all_map_lines


def process_trace(trace):
    if TRACES_FILE_VERSION == 0:
        return trace
    else:
        # [e1~1, e2~2x3, e3~3] then new_trace should be [e1~1, e2~2, e2~2, e2~2, e3~3]
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
        return new_trace


def get_traces_from_dir(dir):
    global next_spec_id, spec_to_id, id_to_spec, raw_specs_id, TRACES_FILE_VERSION
    traces_id_file = os.path.join(dir, 'traces-id.txt')
    specs_frequency_file = os.path.join(dir, 'specs-frequency.csv')
    unique_traces_file = os.path.join(dir, 'unique-traces.txt')
    locations_file = os.path.join(dir, 'locations.txt')
    
    read_from_traces_id = os.path.isfile(traces_id_file)
    
    # traces is [(events (list), frequency (int), spec_id (str)]
    traces = []

    if os.path.isfile(specs_frequency_file) and os.path.isfile(unique_traces_file) and os.path.isfile(locations_file):
        print('Reading traces...')
        id_to_trace = {}
        i = 0
        with open(unique_traces_file) as f:
            line = f.readline().strip()
            if line == '=== UNIQUE TRACES WITH ID ===':
                TRACES_FILE_VERSION = 1

        with open(traces_id_file if read_from_traces_id else unique_traces_file) as f:
            header = False
            for line in f.readlines():
                line = line.strip()
                if not header or not line:
                    header = True
                    continue

                i += 1
                if i % 1000 == 0:
                    print('\tread {} traces'.format(i))

                if read_from_traces_id:
                    match = re.match('^(\d+) \[(.*)\]$', line)
                    if match and match.group(2):
                        # Non-empty events
                        id = match.group(1)
                        trace = match.group(2).split(', ')
                        id_to_trace[id] = process_trace(trace)
                else:
                    match = re.match('^(\d+) (\d+) \[(.*)\]$', line)
                    if match and match.group(3):
                        # Non-empty events
                        id = match.group(1)
                        trace = match.group(3).split(', ')
                        id_to_trace[id] = process_trace(trace)

        print('Reading specs frequency...')
        with open(specs_frequency_file) as f:
            for line in f.readlines():
                line = line.strip()
                if not line or line == 'OK':
                    continue
                
                id, _, spec_to_freq = line.partition(' ')
                if len(spec_to_freq) <= 2 or id not in id_to_trace:
                    print('Error processing spec ID: {}'.format(id))
                    continue
                
                spec_to_freq = spec_to_freq[1:-1]
                for spec_str in spec_to_freq.split(', '):
                    spec, freq = spec_str.split('=')
                    if spec in spec_to_id:
                        spec_id = spec_to_id.get(spec)
                    else:
                        next_spec_id += 1
                        spec_id = str(next_spec_id)
                        spec_to_id[spec] = spec_id
                        id_to_spec[spec_id] = spec
                        if utils.is_raw_spec(spec):
                            raw_specs_id.add(spec_id)
                    traces.append((id_to_trace.get(id), int(freq), spec_id))
        
        print('Reading locations...')
        with open(locations_file) as f:
            map_started = False
            location_id_to_line = {}
            for line in f.readlines():
                line = line.strip();
                if map_started:
                    if line:
                        # if line is 1 com.google.common.primitives.Ints$IntArrayAsList.<clinit>(Ints.java:1)0
                        # then id is 1, method is com.google.common.primitives.Ints$IntArrayAsList.<clinit>, method_loc is 0
                        # and insert location_id_to_line[1] = com.google.common.primitives.Ints$IntArrayAsList.<clinit>:0
                        id, _, location = line.partition(' ')
                        method = location.partition('(')[0]
                        method_loc = location.rpartition(')')[2]
                        location_id_to_line[id] = '{}:{}'.format(method, method_loc)
                    else:
                        # Empty line means it is EOF
                        break
                elif line == '=== LOCATION MAP ===':
                    map_started = True
        return traces, location_id_to_line
    return [], []


def get_event_count(traces, location_id_to_line):
    print('Counting events...')
    counters = {}   # {event: frequency (int)}
    total_events = 0
    total_traces = 0
    
    i = 0
    # traces is [(events (list), frequency (int), spec_id (str)]
    for trace_freq in traces:
        # For example, if trace_str is "([next~1, next~1, next~1, next~1, next~2], 2, 9999)",
        # add {1:next~1: 8, 1:next~2: 2} to result
        events, frequency, spec_id = trace_freq
        total_traces += frequency
        for event in events:
            counters[event] = counters.get(event, 0) + frequency
            total_events += frequency
        
        i += 1
        if i % 1000 == 0:
            print('\tprocessed {} traces'.format(i))
    print('Total {} events and {} traces'.format(total_events, total_traces))
    return counters


def hot_methods(counters, location_id_to_line):
    print('Finding hot methods...')
    method_to_frequency = {} # {method, event frequency}, shows how many events in this method

    i = 0
    # counters is {event: frequency (int)}
    for event, counter in counters.items(): # event (str such as next~1, create~2)
        # event name is str such as next/create, and id is int likes 1/2
        event_name, _, id = event.partition('~')
        method = location_id_to_line.get(id, 'Unknown')
        # location_id_to_line.get(id) returns package.method:method_loc
        # method is package.method
        method_to_frequency[method] = method_to_frequency.get(method, 0) + counter

        i += 1
        if i % 1000 == 0:
            print('\tprocessed {} events'.format(i))

    print('Number of events, method name')
    top_methods = [] # [(method name, number of events)]
    for method_freq in sorted(method_to_frequency.items(), key=lambda x:x[1], reverse=True):
        # number of events, method
        if method_freq[0].strip():
            print('{},{}'.format(method_freq[1], method_freq[0]))
            top_methods.append(method_freq)
    return top_methods

def inspect_method(hot_method):
    print('Starting ' + hot_method)
    logs = []
    logs.append('Inspecting hot method {}...'.format(hot_method))
    related_traces_all = {}
    related_traces_isolated_all = {}
    total_number_related_events = 0
    total_number_related_traces = 0
    total_number_isolated_traces = 0
    total_number_non_isolated_traces = 0
    total_number_isolated_events = 0
    total_number_non_isolated_events = 0
    
    total_number_related_unique_events = 0
    total_number_related_unique_traces = 0
    total_number_isolated_unique_traces = 0
    total_number_non_isolated_unique_traces = 0
    total_number_isolated_unique_events = 0
    total_number_non_isolated_unique_events = 0
    
    total_number_non_isolated_events_in_imm = 0
    total_number_non_isolated_unique_events_in_imm = 0
    
    related_traces = []
    related_id = method_to_related_id.get(hot_method, set())
    # traces is [(events (list), frequency (int), spec_id (str)]
    for traces, methods in traces_to_related_methods:
        if hot_method in methods:
            related_traces.append(traces)
        

    logs.append('Checking for isolation...')
    related_isolated_traces = [] # find list of traces that only have events in hot methods
    related_isolated_specs = {} # specs to number of traces (x frequency)
    related_isolated_specs_unique = {} # specs to number of unique traces
    
    related_isolated_specs_events = {} # specs to number of events (x frequency)
    related_isolated_specs_unique_events = {} # specs to number of unique events
    
    unrelated_isolated_specs = {} # specs to number of traces (x frequency)
    unrelated_isolated_specs_unique = {} # specs to number of unique traces
    
    unrelated_isolated_specs_events = {} # specs to number of events (x frequency)
    unrelated_isolated_specs_unique_events = {} # specs to number of unique events
    
    unrelated_isolated_specs_events_in_imm = {} # specs to number of events (x frequency)
    unrelated_isolated_specs_unique_events_in_imm = {} # specs to number of unique events

    i = 0
    # related_traces is [(events (list), frequency (int), spec_id (str)]
    for related_trace in related_traces:
        total_number_related_traces += related_trace[1]
        total_number_related_unique_traces += 1
        # related_trace is in related_isolated_traces if all events are in related_id
        isolated = True

        event_in_imm = 0
        event_outside_imm = 0
        
        events, frequency, spec_id = related_trace
        if spec_id in raw_specs_id:
            # We don't check for raw spec, not IMM anyway
            isolated = False
        else:
            for event in events:
                # event name is str such as next/create, and id is int likes 1/2
                event_name, _, id = event.partition('~')
                if id not in related_id:
                    isolated = False # discard related_trace because it has at least one event OUTSIDE hot methods
                    event_outside_imm += 1
                else:
                    total_number_related_events += frequency
                    total_number_related_unique_events += 1
                    event_in_imm += 1

        spec_name = id_to_spec.get(spec_id, 'Unknown')

        if isolated:
            # TRACES
            related_isolated_traces.append(related_trace)
            total_number_isolated_traces += frequency
            total_number_isolated_unique_traces += 1
            
            related_isolated_specs[spec_name] = related_isolated_specs.get(spec_name, 0) + frequency
            related_isolated_specs_unique[spec_name] = related_isolated_specs_unique.get(spec_name, 0) + 1
            
            # EVENTS
            trace_length = len(events)
            total_number_isolated_events += (trace_length * frequency)
            total_number_isolated_unique_events += trace_length
            
            related_isolated_specs_events[spec_name] = related_isolated_specs_events.get(spec_name, 0) + (trace_length * frequency)
            related_isolated_specs_unique_events[spec_name] = related_isolated_specs_unique_events.get(spec_name, 0) + trace_length
        else:
            # TRACES
            total_number_non_isolated_traces += frequency
            total_number_non_isolated_unique_traces += 1
            
            unrelated_isolated_specs[spec_name] = unrelated_isolated_specs.get(spec_name, 0) + frequency
            unrelated_isolated_specs_unique[spec_name] = unrelated_isolated_specs_unique.get(spec_name, 0) + 1
            
            # EVENTS
            trace_length = len(events)
            total_number_non_isolated_events += (trace_length * frequency)
            total_number_non_isolated_unique_events += trace_length
            
            unrelated_isolated_specs_events[spec_name] = unrelated_isolated_specs_events.get(spec_name, 0) + (trace_length * frequency)
            unrelated_isolated_specs_unique_events[spec_name] = unrelated_isolated_specs_unique_events.get(spec_name, 0) + trace_length
            
            unrelated_isolated_specs_events_in_imm[spec_name] = unrelated_isolated_specs_events_in_imm.get(spec_name, 0) + (event_in_imm * frequency)
            unrelated_isolated_specs_unique_events_in_imm[spec_name] = unrelated_isolated_specs_unique_events_in_imm.get(spec_name, 0) + event_in_imm
            
            total_number_non_isolated_events_in_imm += (event_in_imm * frequency)
            total_number_non_isolated_unique_events_in_imm += event_in_imm

        i += 1
        if i % 1000 == 0:
            logs.append('\tprocessed {} traces'.format(i))

    # number of events in hot methods, number of traces that have at least one event in hot methods, number of traces that only have events in hot methods,
    # and number of traces that have events in hot method but also have events outside hot methods
    logs.append('{},{},{},{}'.format(total_number_related_events, total_number_related_traces, total_number_isolated_traces, total_number_non_isolated_traces))
    logs.append('Total {} ({} unique) events are in hot method'.format(total_number_related_events, total_number_related_unique_events))
    logs.append('Total {} ({} unique) traces are in hot method'.format(total_number_related_traces, total_number_related_unique_traces))
    logs.append('Total {} ({} unique) isolated traces are in hot method'.format(total_number_isolated_traces, total_number_isolated_unique_traces))
    logs.append('Total {} ({} unique) non-isolated traces that have events in hot method'.format(total_number_non_isolated_traces, total_number_non_isolated_unique_traces))
    logs.append('Total {} ({} unique) events are in isolated traces'.format(total_number_isolated_events, total_number_isolated_unique_events))
    logs.append('Total {} ({} unique) events are in non-isolated traces ({} / {} unique are in hot method)'.format(total_number_non_isolated_events, total_number_non_isolated_unique_events, total_number_non_isolated_events_in_imm, total_number_non_isolated_unique_events_in_imm))
    
    related_isolated_specs_data = []
    if related_isolated_specs:
        # for the traces that are isolated in the hot method, what specs are they?
        logs.append('Specs that have isolated traces:')
        for spec, freq in dict(sorted(related_isolated_specs.items(), key=lambda item: item[1], reverse=True)).items():
            spec_name = spec
            if spec_name != 'Unknown':
                spec_name = spec[:-1*len('Monitor')] # remove the word Monitor from spec name

            related_isolated_specs_data.append({'spec_name': spec_name, 'traces': freq, 'unique_traces': related_isolated_specs_unique.get(spec), 'events': related_isolated_specs_events.get(spec), 'unique_events': related_isolated_specs_unique_events.get(spec)})
            logs.append('\t' + spec_name + ' ({} traces / {} unique traces) ({} events / {} unique events)'.format(freq, related_isolated_specs_unique.get(spec), related_isolated_specs_events.get(spec), related_isolated_specs_unique_events.get(spec)))

    unrelated_isolated_specs_data = []
    if unrelated_isolated_specs:
        # for the traces that are NOT isolated in the hot method, what specs are they?
        logs.append('Specs that have non-isolated traces:')
        for spec, freq in dict(sorted(unrelated_isolated_specs.items(), key=lambda item: item[1], reverse=True)).items():
            spec_name = spec
            if spec_name != 'Unknown':
                spec_name = spec[:-1*len('Monitor')] # remove the word Monitor from spec name
                
            unrelated_isolated_specs_data.append({'spec_name': spec_name, 'traces': freq, 'unique_traces': unrelated_isolated_specs_unique.get(spec), 'events': unrelated_isolated_specs_events.get(spec), 'unique_events': unrelated_isolated_specs_unique_events.get(spec)})
            logs.append('\t' + spec_name + ' ({} traces / {} unique traces) ({} events / {} unique events) ({} events / {} unique events in hot method)'.format(freq, unrelated_isolated_specs_unique.get(spec), unrelated_isolated_specs_events.get(spec), unrelated_isolated_specs_unique_events.get(spec), unrelated_isolated_specs_events_in_imm.get(spec), unrelated_isolated_specs_unique_events_in_imm.get(spec)))

    classification = classifier.classify(
        {
            'hot_method': hot_method,
            'traces_path': traces_path,
            'total_number_related_events': total_number_related_events,
            'total_number_related_unique_events': total_number_related_unique_events,
            'total_number_related_traces': total_number_related_traces,
            'total_number_related_unique_traces': total_number_related_unique_traces,
            'total_number_isolated_traces': total_number_isolated_traces,
            'total_number_isolated_unique_traces': total_number_isolated_unique_traces,
            'total_number_non_isolated_traces': total_number_non_isolated_traces,
            'total_number_non_isolated_unique_traces': total_number_non_isolated_unique_traces,
            'related_isolated_specs_data': related_isolated_specs_data,
            'unrelated_isolated_specs_data': unrelated_isolated_specs_data,
            'total_number_isolated_events': total_number_isolated_events,
            'total_number_isolated_unique_events': total_number_isolated_unique_events,
            'total_number_non_isolated_events': total_number_non_isolated_events,
            'total_number_non_isolated_unique_events': total_number_non_isolated_unique_events
        }
    )
    logs.append(classification)
    print('Finish ' + hot_method)
    return (hot_method, logs)

def main(argv=None):
    argv = argv or sys.argv
    
    if len(argv) < 2:
        print('Usage: python3 imm_locator.py <path-to-traces-dir> [inspect-method] [number-of-threads]')
        exit(1)
 
    global traces_path, traces, location_id_to_line, traces_to_related_methods, method_to_related_id
    traces_path = argv[1]
    
    traces, location_id_to_line = get_all_traces()
    counters = get_event_count(traces, location_id_to_line)
    
    if len(argv) == 2:
        hot_methods(counters, location_id_to_line)
    elif argv[2].startswith('@'):
        if len(argv) == 4:
            global THREADS_MAX
            THREADS_MAX = int(argv[3])

        processes = []
        methods = []
        results = []
        
        top_x = int(argv[2].split('@')[1])
        print('Inspecting top {} IMM'.format(top_x))
        for hot_method in hot_methods(counters, location_id_to_line)[:top_x]:
            # hot_method is [(method name, number of events)]
            if hot_method[1] <= 1:
                print('^^^ Last method that contains more than one event ^^^')
                break
            methods.append(hot_method[0])

        # MAP TRACES TO RELATIVED EVENTS and METHOD to RELATIVED ID
        related_id = {}  # map location id to related methods
        traces_to_related_methods = []
        method_to_related_id = {} # map method to related IDs
        for location_id, location_line in location_id_to_line.items():
            tmp = set()
            for m in methods:
                if location_line == m:
                    tmp.add(m)
            related_id[location_id] = tmp
        for trace in traces:
            related_methods = set()
            processed_events = set()
            for event in trace[0]:
                if event in processed_events:
                    continue
                processed_events.add(event)
                # event name is str such as next/create, and id is int likes 1/2
                event_name, _, id = event.partition('~')
                for method in related_id.get(id, set()):
                    related_methods.add(method)
                    if method in method_to_related_id:
                        method_to_related_id[method].add(id)
                    else:
                        method_to_related_id[method] = set()
                        method_to_related_id[method].add(id)
            traces_to_related_methods.append((trace, related_methods))


        if THREADS_MAX > 1:
            with multiprocessing.Pool(processes=THREADS_MAX) as pool:
                results = pool.map(inspect_method, methods)
        else:
            for method in methods:
                results.append(inspect_method(method))

        print('')
        index = 0
        for result in results:
            index += 1
            print('#{}'.format(index))
            for i in result[1]:
                print(i)
            print('')
    else:
        for i in inspect_method(argv[2])[1]:
            print(i)

if __name__ == '__main__':
    csv.field_size_limit(sys.maxsize)
    main()
