#!/bin/bash
#
# Fetch pipelines-as-code E2E test workflow runs
# Usage: ./fetch_pac_e2e_jobs.sh -s 7d
#

set -euo pipefail

REPO="openshift-pipelines/pipelines-as-code"
SINCE=""
UNTIL=""
STATUS=""
LIMIT=100
WORKFLOW_FILTER="e2e"  # Filter for E2E workflows

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Fetch pipelines-as-code E2E test runs within a specified time period.

Options:
    -s, --since DURATION  Time period (e.g., 7d, 24h, 2w)
    -u, --until DATE      End date (YYYY-MM-DD), defaults to now
    -S, --status STATUS   Filter: completed, in_progress, queued, failure, success
    -l, --limit N         Max results (default: 100)
    -a, --all             Show all workflows, not just E2E
    -f, --failed          Show failed jobs for each workflow run
    -c, --context         Include failure context (10 lines before each test failure)
    -C, --cancelled       Include cancelled workflow runs
    -h, --help            Show this help

Duration formats for --since:
    Nd  - N days ago (e.g., 7d = 7 days ago)
    Nh  - N hours ago (e.g., 24h = 24 hours ago)
    Nw  - N weeks ago (e.g., 2w = 2 weeks ago)

Examples:
    $(basename "$0") -s 7d
    $(basename "$0") -s 24h --status failure
    $(basename "$0") -s 2w --failed
    $(basename "$0") -s 7d -f -C              # Include cancelled runs
EOF
    exit 0
}

SHOW_ALL=false
SHOW_FAILED=false
SHOW_CONTEXT=false
INCLUDE_CANCELLED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--since)    SINCE="$2"; shift 2 ;;
        -u|--until)    UNTIL="$2"; shift 2 ;;
        -S|--status)   STATUS="$2"; shift 2 ;;
        -l|--limit)    LIMIT="$2"; shift 2 ;;
        -a|--all)      SHOW_ALL=true; shift ;;
        -f|--failed)   SHOW_FAILED=true; shift ;;
        -c|--context)  SHOW_CONTEXT=true; shift ;;
        -C|--cancelled) INCLUDE_CANCELLED=true; shift ;;
        -h|--help)     usage ;;
        *)             echo "Unknown option: $1"; usage ;;
    esac
done

# Parse duration format (7d, 24h, 2w) to ISO date
parse_duration() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo ""
        return
    fi
    
    # Match patterns like 7d, 24h, 2w
    if [[ "$input" =~ ^([0-9]+)([dhw])$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        case "$unit" in
            d) date -d "$num days ago" -u +"%Y-%m-%dT%H:%M:%SZ" ;;
            h) date -d "$num hours ago" -u +"%Y-%m-%dT%H:%M:%SZ" ;;
            w) date -d "$num weeks ago" -u +"%Y-%m-%dT%H:%M:%SZ" ;;
        esac
    else
        # Fallback: try to parse as date
        date -d "$input" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$input"
    fi
}

SINCE_ISO=$(parse_duration "$SINCE")
UNTIL_ISO=$(parse_duration "$UNTIL")

# Show failed jobs for each workflow run
if [[ "$SHOW_FAILED" == true ]]; then
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  Failed Jobs in Pipelines-as-Code E2E Test Runs"
    echo "  Repository: $REPO"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    [[ -n "$SINCE" ]] && echo "  Since: $SINCE_ISO"
    [[ -n "$UNTIL" ]] && echo "  Until: $UNTIL_ISO"
    $INCLUDE_CANCELLED && echo "  Including: cancelled runs"
    echo ""
    
    # Fetch failed runs
    FAILED_RUNS=$(gh run list -R "$REPO" -L "$LIMIT" --status failure \
        --json databaseId,workflowName,headBranch,headSha,createdAt,url,attempt,conclusion | \
        jq -r --arg since "$SINCE_ISO" --arg until "$UNTIL_ISO" --argjson all "$SHOW_ALL" --arg filter "$WORKFLOW_FILTER" '
            [.[] | select(
                ($since == "" or .createdAt >= $since) and
                ($until == "" or .createdAt <= $until) and
                ($all or (.workflowName | ascii_downcase | contains($filter)))
            )]
        ')
    
    # Fetch cancelled runs if requested
    if [[ "$INCLUDE_CANCELLED" == true ]]; then
        CANCELLED_RUNS=$(gh run list -R "$REPO" -L "$LIMIT" --status cancelled \
            --json databaseId,workflowName,headBranch,headSha,createdAt,url,attempt,conclusion | \
            jq -r --arg since "$SINCE_ISO" --arg until "$UNTIL_ISO" --argjson all "$SHOW_ALL" --arg filter "$WORKFLOW_FILTER" '
                [.[] | select(
                    ($since == "" or .createdAt >= $since) and
                    ($until == "" or .createdAt <= $until) and
                    ($all or (.workflowName | ascii_downcase | contains($filter)))
                )]
            ')
        # Merge failed and cancelled runs
        RUNS=$(echo "$FAILED_RUNS" "$CANCELLED_RUNS" | jq -s 'add | sort_by(.createdAt) | reverse')
    else
        RUNS="$FAILED_RUNS"
    fi
    
    
    RUN_COUNT=$(echo "$RUNS" | jq 'length')
    
    if [[ "$RUN_COUNT" -eq 0 ]]; then
        echo "No failed E2E runs found in the specified time period."
        exit 0
    fi
    
    echo "Found $RUN_COUNT failed run(s). Fetching job details..."
    echo ""
    
    # Temp files to collect data
    FAILED_TESTS_FILE=$(mktemp)
    FAILURE_CONTEXT_FILE=$(mktemp)
    trap "rm -f $FAILED_TESTS_FILE $FAILURE_CONTEXT_FILE" EXIT
    
    # Iterate through each failed run and get failed jobs
    echo "$RUNS" | jq -r '.[] | "\(.databaseId)|\(.workflowName)|\(.headBranch)|\(.createdAt)|\(.url)|\(.attempt // 1)|\(.conclusion // "failure")|\(.headSha // "")"' | \
    while IFS='|' read -r run_id workflow branch created url attempt conclusion sha; do
        echo "───────────────────────────────────────────────────────────────────────────────"
        
        # Build status indicator
        STATUS_ICON="✗"
        [[ "$conclusion" == "cancelled" ]] && STATUS_ICON="⊘"
        
        ATTEMPT_INFO=""
        [[ "$attempt" -gt 1 ]] && ATTEMPT_INFO=" (attempt #$attempt)"
        
        echo "▶ Run #$run_id: $workflow$ATTEMPT_INFO"
        echo "  Branch: $branch | Created: ${created:0:16} | Status: $STATUS_ICON $conclusion"
        [[ -n "$sha" ]] && echo "  Commit: ${sha:0:8}"
        echo "  URL: $url"
        echo ""
        
        # Get failed jobs for this run
        JOBS_INFO=$(gh run view "$run_id" -R "$REPO" --json jobs 2>/dev/null || echo '{"jobs":[]}')
        
        echo "$JOBS_INFO" | jq -r '
            .jobs[] | select(.conclusion == "failure") |
            "  ✗ \(.name)\n    Status: \(.conclusion) | Duration: \(
                if .startedAt and .completedAt then
                    ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601) | . / 60 | floor | tostring) + "m"
                else "—" end
            )\n    Steps failed:"
        ' 2>/dev/null || echo "  (Could not fetch job details)"
        
        # Get failed steps within failed jobs
        echo "$JOBS_INFO" | jq -r '
            .jobs[] | select(.conclusion == "failure") |
            .steps[] | select(.conclusion == "failure") |
            "      - \(.name)"
        ' 2>/dev/null || true
        
        # Check if any failed step is an e2e test step
        E2E_FAILED_JOBS=$(echo "$JOBS_INFO" | jq -r '
            .jobs[] | select(.conclusion == "failure") |
            select(
                (.steps[]? | select(.conclusion == "failure") | .name | ascii_downcase) |
                (contains("e2e") or contains("test"))
            ) | .databaseId
        ' 2>/dev/null | sort -u)
        
        if [[ -n "$E2E_FAILED_JOBS" ]]; then
            echo ""
            echo "    📋 Fetching failed test names from logs..."
            
            # Download logs for this run and extract failed tests
            LOG_OUTPUT=$(gh run view "$run_id" -R "$REPO" --log 2>/dev/null || true)
            
            if [[ -n "$LOG_OUTPUT" ]]; then
                # Extract failed test names from Go test output
                # Patterns: "--- FAIL: TestName" or "FAIL TestName" or "=== FAIL: TestName"
                FAILED_TESTS=$(echo "$LOG_OUTPUT" | grep -oE '(--- FAIL: |FAIL\s+|=== FAIL:\s+)(Test[A-Za-z0-9_/]+)' | \
                    sed -E 's/(--- FAIL: |FAIL\s+|=== FAIL:\s+)//' | sort -u || true)
                
                if [[ -n "$FAILED_TESTS" ]]; then
                    echo "    Failed tests in this run:"
                    echo "$FAILED_TESTS" | while read -r test_name; do
                        echo "      ✗ $test_name"
                        echo "$test_name" >> "$FAILED_TESTS_FILE"
                    done
                    
                    # Save failure context if requested
                    if [[ "$SHOW_CONTEXT" == true ]]; then
                        CONTEXT=$(echo "$LOG_OUTPUT" | grep -B10 -- "--- FAIL.*Test" || true)
                        if [[ -n "$CONTEXT" ]]; then
                            echo "=== Run #$run_id: $workflow ===" >> "$FAILURE_CONTEXT_FILE"
                            echo "$CONTEXT" >> "$FAILURE_CONTEXT_FILE"
                            echo "" >> "$FAILURE_CONTEXT_FILE"
                        fi
                    fi
                else
                    echo "    (No specific test failures extracted from logs)"
                fi
            else
                echo "    (Could not fetch logs)"
            fi
        fi
        
        echo ""
    done
    
    # Print summary table of failed tests
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  SUMMARY: Failed Tests Frequency"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    
    if [[ -s "$FAILED_TESTS_FILE" ]]; then
        printf "%-6s  %s\n" "COUNT" "TEST NAME"
        printf "%-6s  %s\n" "-----" "---------"
        sort "$FAILED_TESTS_FILE" | uniq -c | sort -rn | \
        while read -r count test_name; do
            printf "%-6s  %s\n" "$count" "$test_name"
        done
        echo ""
        echo "Total unique failed tests: $(sort -u "$FAILED_TESTS_FILE" | wc -l)"
        echo "Total test failures: $(wc -l < "$FAILED_TESTS_FILE")"
    else
        echo "No specific test failures were extracted from the logs."
        echo "(Tests may have failed for infrastructure reasons, or log format wasn't recognized)"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    
    # Output failure context section if requested and available
    if [[ "$SHOW_CONTEXT" == true ]] && [[ -s "$FAILURE_CONTEXT_FILE" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "  FAILURE CONTEXT (10 lines before each test failure)"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo ""
        cat "$FAILURE_CONTEXT_FILE"
        echo "═══════════════════════════════════════════════════════════════════════════════"
    fi
    
    exit 0
fi

# Build gh run list command
CMD="gh run list -R $REPO -L $LIMIT"

[[ -n "$STATUS" ]] && CMD="$CMD --status $STATUS"

# Fetch runs and display table
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Pipelines-as-Code E2E Test Runs"
echo "  Repository: $REPO"
echo "═══════════════════════════════════════════════════════════════════════════════"
[[ -n "$SINCE" ]] && echo "  Since: $SINCE_ISO"
[[ -n "$UNTIL" ]] && echo "  Until: $UNTIL_ISO"
[[ -n "$STATUS" ]] && echo "  Status: $STATUS"
$SHOW_ALL && echo "  Showing: ALL workflows" || echo "  Showing: E2E workflows only"
echo ""

$CMD --json databaseId,workflowName,headBranch,status,conclusion,createdAt,event,attempt | \
jq -r --arg since "$SINCE_ISO" --arg until "$UNTIL_ISO" --argjson all "$SHOW_ALL" --arg filter "$WORKFLOW_FILTER" '
    ["RUN_ID", "WORKFLOW", "BRANCH", "EVENT", "STATUS", "RESULT", "ATTEMPT", "CREATED"],
    ["-------", "--------", "------", "-----", "------", "------", "-------", "-------"],
    (.[] | select(
        ($since == "" or .createdAt >= $since) and
        ($until == "" or .createdAt <= $until) and
        ($all or (.workflowName | ascii_downcase | contains($filter)))
    ) | [
        .databaseId,
        .workflowName[0:30],
        .headBranch[0:20],
        .event[0:12],
        .status,
        (.conclusion // "—"),
        ("#" + ((.attempt // 1) | tostring)),
        .createdAt[0:16]
    ]) | @tsv
' | column -t -s $'\t'

echo ""
