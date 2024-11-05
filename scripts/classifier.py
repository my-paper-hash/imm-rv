#!/usr/bin/env python3
from utils import utils

def classify(data):
    categories = classify_hot_method(data)
    
    seen = set()
    categories = [category for category in categories if not (category in seen or seen.add(category))]
    categories[1:] = sorted(categories[1:])
    return 'Classifier (' + data['hot_method'] + '): ' + ','.join(categories)

def classify_hot_method(data):
    """
    {
        'hot_method': hot_method,
        'traces_path': traces_path,
        'total_number_related_traces': total_number_related_traces,
        'total_number_related_unique_traces': total_number_related_unique_traces,
        'total_number_isolated_traces': total_number_isolated_traces,
        'total_number_isolated_unique_traces': total_number_isolated_unique_traces,
        'total_number_non_isolated_traces': total_number_non_isolated_traces,
        'total_number_non_isolated_unique_traces': total_number_non_isolated_unique_traces,
        'related_isolated_specs_data': related_isolated_specs_data,
        'unrelated_isolated_specs_data': unrelated_isolated_specs_data
    }
    """
    
    cut = 'CUT' if utils.is_in_CUT(data['hot_method'], data['traces_path']) else 'LIB'

    if data['total_number_related_traces'] == data['total_number_related_unique_traces']:
        # has x traces, are all unique, cannot be IMM
        return [cut, 'NOT_REDUNDANT_TRACES']

    categories = [cut]
    if data['related_isolated_specs_data']:
        # For all traces that are isoalted in hot method
        for spec in data['related_isolated_specs_data']:
            raw = 'RAW_' if utils.is_raw_spec(spec['spec_name']) else ''
            if spec['unique_traces'] > 1:
                # multiple unique traces
                if spec['unique_traces'] == spec['traces']:
                    # has x traces, they are all unique, cannot be IMM
                    categories.append(raw + 'ISOLATED_MULTIPLE_UNIQUE_NO_REDUNDANT')
                else:
                    # has x traces, has y unique traces, y < x (so some traces are redundant) # <- start next?
                    categories.append(raw + 'ISOLATED_MULTIPLE_UNIQUE')
            elif spec['unique_traces'] == 1 and spec['traces'] == 1:
                categories.append(raw + 'ISOLATED_SINGLE_TRACE')
            else:
                # best case, one unique trace (total traces > 1)
                categories.append(raw + 'ISOLATED_ONE_UNIQUE')
    if data['unrelated_isolated_specs_data']:
        # For all traces that are isoalted in hot method
        for spec in data['unrelated_isolated_specs_data']:
            raw = 'RAW_' if utils.is_raw_spec(spec['spec_name']) else ''
            if spec['unique_traces'] > 1:
                # multiple unique traces
                if spec['unique_traces'] == spec['traces']:
                    categories.append(raw + 'NOT_ISOLATED_MULTIPLE_UNIQUE_NO_REDUNDANT')
                else:
                    categories.append(raw + 'NOT_ISOLATED_MULTIPLE_UNIQUE')
            elif spec['unique_traces'] == 1 and spec['traces'] == 1:
                categories.append(raw + 'NOT_ISOLATED_SINGLE_TRACE')
            else:
                categories.append(raw + 'NOT_ISOLATED_ONE_UNIQUE')

    return categories
