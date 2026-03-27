#!/usr/bin/env python3
"""
Extract GitHub API call records from any PAC controller log and emit CSV to stdout.

Parses both container log format ("<ts> stdout F <json>") and plain JSON logs.

Usage:
    python3 extract_api_calls_csv.py [LOG_FILE_OR_GLOB ...]
    cat some.log | python3 extract_api_calls_csv.py

Examples:
    python3 extract_api_calls_csv.py containers/*.log
    python3 extract_api_calls_csv.py n*/kind-control-plane/containers/*.log > all.csv
    cat ghe-controller.log | python3 extract_api_calls_csv.py
"""

import json, glob, os, csv, sys
from collections import defaultdict, Counter

FIELDS = [
    "source_file",
    "event_id", "event_sha", "event_type",
    "timestamp",
    "namespace", "pr", "source_branch", "target_branch",
    "source_repo_url", "organization", "repository",
    "controller_label", "provider",
    "operation", "duration_ms", "url_path",
    "rate_limit_remaining", "status_code", "github_request_id",
    "total_calls_in_event", "call_index", "url_call_count", "is_duplicate",
]

META_MAP = [
    ('event-sha',        'event_sha'),
    ('event-type',       'event_type'),
    ('ts',               'timestamp'),
    ('namespace',        'namespace'),
    ('pr',               'pr'),
    ('source-branch',    'source_branch'),
    ('target-branch',    'target_branch'),
    ('source-repo-url',  'source_repo_url'),
    ('organization',     'organization'),
    ('repository',       'repository'),
    ('controller_label', 'controller_label'),
    ('provider',         'provider'),
]


def parse_line(line):
    """Return parsed JSON dict from a log line, or None."""
    stripped = line.strip()
    if not stripped:
        return None
    # Try container log format: "<ts> stdout F <json>"
    parts = stripped.split(' ', 3)
    if len(parts) == 4:
        try:
            return json.loads(parts[3])
        except Exception:
            pass
    # Fall back to plain JSON
    try:
        return json.loads(stripped)
    except Exception:
        return None


def process_lines(lines, source_file=''):
    event_meta = {}
    event_calls = defaultdict(list)

    for line in lines:
        d = parse_line(line)
        if d is None:
            continue

        eid = d.get('event-id')
        if not eid:
            continue

        if eid not in event_meta:
            event_meta[eid] = {f: '' for f in FIELDS}
            event_meta[eid].update({'source_file': source_file, 'event_id': eid})

        m = event_meta[eid]
        for src, dst in META_MAP:
            if d.get(src) and not m[dst]:
                m[dst] = d[src]

        if d.get('msg') == 'GitHub API call completed':
            event_calls[eid].append({
                'operation':            d.get('operation', ''),
                'duration_ms':          d.get('duration_ms', ''),
                'url_path':             d.get('url_path', ''),
                'rate_limit_remaining': d.get('rate_limit_remaining', ''),
                'status_code':          d.get('status_code', ''),
                'github_request_id':    d.get('github_request_id', ''),
            })

    return event_meta, event_calls


def emit(writer, event_meta, event_calls):
    for eid in sorted(event_meta.keys()):
        calls = event_calls.get(eid, [])
        if not calls:
            continue
        meta = event_meta[eid]
        url_op_counts = Counter((c['url_path'], c['operation']) for c in calls)
        total = len(calls)
        for i, call in enumerate(calls, 1):
            url_cnt = url_op_counts[(call['url_path'], call['operation'])]
            writer.writerow({**meta, **call,
                             'total_calls_in_event': total,
                             'call_index': i,
                             'url_call_count': url_cnt,
                             'is_duplicate': url_cnt > 1})


def main():
    writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS, extrasaction='ignore')
    writer.writeheader()

    args = sys.argv[1:]

    if not args:
        meta, calls = process_lines(sys.stdin, source_file='<stdin>')
        emit(writer, meta, calls)
        return

    log_files = []
    for pattern in args:
        expanded = glob.glob(pattern, recursive=True)
        log_files.extend(sorted(expanded) if expanded else [pattern])

    for path in log_files:
        with open(path) as f:
            meta, calls = process_lines(f, source_file=os.path.basename(path))
        emit(writer, meta, calls)


if __name__ == '__main__':
    main()
