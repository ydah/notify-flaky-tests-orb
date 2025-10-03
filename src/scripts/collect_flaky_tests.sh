#!/bin/bash -eu

if [ "${DEBUG}" = "true" ]; then
    set -x
    echo "Debug mode enabled"
fi

if [ "${PROJECT_SLUG}" = '' ]; then
    PROJECT_SLUG=$(echo "$CIRCLE_BUILD_URL" | sed -e "s|https://circleci.com/||g" -e "s|/[0-9]*$||g")
fi

echo "Project slug: ${PROJECT_SLUG}"

TOKEN=$(eval echo \""$CIRCLE_TOKEN_PARAM"\")

if [ -z "$TOKEN" ]; then
    echo "Error: CIRCLE_TOKEN is not set. Please set the CIRCLE_TOKEN environment variable."
    exit 1
fi

total_flaky_tests=$(echo "$res" | jq '.total_flaky_tests')
echo "Total flaky tests found: $total_flaky_tests"

if [ "$total_flaky_tests" = '0' ] || [ "$total_flaky_tests" = 'null' ]; then
    echo "No flaky tests found! This is good news."
    circleci-agent step halt
fi

filtered_tests="$res"

if [ "$MINIMUM_FLAKE_COUNT" -gt 1 ]; then
    echo "Filtering tests with less than $MINIMUM_FLAKE_COUNT flakes..."
    filtered_tests=$(echo "$filtered_tests" | jq ".flaky_tests |= map(select(.times_flaked >= $MINIMUM_FLAKE_COUNT))")
fi

if [ -n "$TEST_FILE_PATTERN" ]; then
    echo "Filtering tests by pattern: $TEST_FILE_PATTERN"
    filtered_tests=$(echo "$filtered_tests" | jq ".flaky_tests |= map(select(.source | test(\"$TEST_FILE_PATTERN\")))")
fi

flaky_tests_count=$(echo "$filtered_tests" | jq '.flaky_tests | length')

if [ "$flaky_tests_count" = '0' ]; then
    echo "No tests match the specified filters."
    circleci-agent step halt
fi

echo "Flaky tests after filtering: $flaky_tests_count"

if [ "$INCLUDE_STATISTICS" = "true" ]; then
    echo "Calculating statistics..."

    total_flakes=$(echo "$filtered_tests" | jq '[.flaky_tests[].times_flaked] | add')

    if [ "$flaky_tests_count" -gt 0 ]; then
        avg_flake_rate=$(echo "$filtered_tests" | jq '[.flaky_tests[].times_flaked] | add / length | floor')
    else
        avg_flake_rate=0
    fi

    most_flaky_job=$(echo "$filtered_tests" | jq -r '.flaky_tests | group_by(.job_name) | map({job: .[0].job_name, count: length}) | max_by(.count) | .job // "N/A"')

    most_flaky_class=$(echo "$filtered_tests" | jq -r '.flaky_tests | group_by(.classname) | map({class: .[0].classname, count: length}) | max_by(.count) | .class // "N/A"')
fi

if [ "$OUTPUT_METRICS" = "true" ]; then
    echo "Generating metrics file..."

    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    case "$METRICS_FORMAT" in
        "json")
            metrics_file="${METRICS_FILE_PATH}.json"
            echo "$filtered_tests" | jq --arg ts "$timestamp" --arg proj "$PROJECT_SLUG" \
                '{timestamp: $ts, project: $proj, total_flaky_tests: .total_flaky_tests, tests: .flaky_tests | map({name: .test_name, classname: .classname, source: .source, times_flaked: .times_flaked, job_name: .job_name, last_flaked: .workflow_created_at})}' \
                > "$metrics_file"
            echo "Metrics saved to: $metrics_file"
            ;;

        "csv")
            metrics_file="${METRICS_FILE_PATH}.csv"
            echo "timestamp,project,test_name,classname,source,times_flaked,job_name,last_flaked" > "$metrics_file"
            echo "$filtered_tests" | jq -r --arg ts "$timestamp" --arg proj "$PROJECT_SLUG" \
                '.flaky_tests[] | [$ts, $proj, .test_name, .classname, .source, .times_flaked, .job_name, .workflow_created_at] | @csv' \
                >> "$metrics_file"
            echo "Metrics saved to: $metrics_file"
            ;;

        "prometheus")
            metrics_file="${METRICS_FILE_PATH}.prom"
            {
                echo "# HELP circleci_flaky_tests_total Total number of flaky tests"
                echo "# TYPE circleci_flaky_tests_total gauge"
                echo "circleci_flaky_tests_total{project=\"$PROJECT_SLUG\"} $flaky_tests_count"
                echo ""
                echo "# HELP circleci_flaky_test_flakes Number of times each test has flaked"
                echo "# TYPE circleci_flaky_test_flakes gauge"
                echo "$filtered_tests" | jq -r --arg proj "$PROJECT_SLUG" \
                    '.flaky_tests[] | "circleci_flaky_test_flakes{project=\"" + $proj + "\",test=\"" + .test_name + "\",class=\"" + .classname + "\",job=\"" + .job_name + "\"} " + (.times_flaked | tostring)'
            } > "$metrics_file"
            echo "Metrics saved to: $metrics_file"
            ;;
    esac
fi

echo "Creating Slack notification template..."

template=$(cat << EOS
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "${NOTIFICATION_TITLE} in *${PROJECT_SLUG}* project."
      }
    }
  ]
}
EOS
)

if [ "$INCLUDE_STATISTICS" = "true" ]; then
    stats_template=$(cat << EOS
{
  "type": "section",
  "fields": [
    {
      "type": "mrkdwn",
      "text": "*Total Flaky Tests:* ${flaky_tests_count}"
    },
    {
      "type": "mrkdwn",
      "text": "*Total Flakes:* ${total_flakes}"
    },
    {
      "type": "mrkdwn",
      "text": "*Average Flakes per Test:* ${avg_flake_rate}"
    },
    {
      "type": "mrkdwn",
      "text": "*Time Period:* Last ${TIME_RANGE} days"
    },
    {
      "type": "mrkdwn",
      "text": "*Most Flaky Job:* ${most_flaky_job}"
    },
    {
      "type": "mrkdwn",
      "text": "*Most Flaky Class:* ${most_flaky_class}"
    }
  ]
}
EOS
)
    template=$(echo "$template" | jq ".blocks |= . + [$stats_template]")
fi

if [ "$GROUP_BY_CLASS" = "true" ]; then
    echo "Grouping tests by class..."

    classes=$(echo "$filtered_tests" | jq -r '.flaky_tests[].classname' | sort -u)

    while IFS= read -r class; do
        if [ -n "$class" ]; then
            class_tests=$(echo "$filtered_tests" | jq --arg c "$class" '.flaky_tests | map(select(.classname == $c))')
            class_count=$(echo "$class_tests" | jq 'length')
            class_total_flakes=$(echo "$class_tests" | jq '[.[].times_flaked] | add')

            class_template=$(cat << EOS
{
  "type": "divider"
},
{
  "type": "section",
  "text": {
    "type": "mrkdwn",
    "text": "*Class: ${class}*\n_${class_count} tests, ${class_total_flakes} total flakes_"
  }
}
EOS
)
            template=$(echo "$template" | jq ".blocks |= . + [$class_template]")

            for i in $(seq 0 $((class_count - 1))); do
                test_data=$(echo "$class_tests" | jq ".[$i]")
                add_test_to_template "$test_data"
            done
        fi
    done <<< "$classes"
else
    for i in $(seq 0 $((flaky_tests_count - 1))); do
        test_data=$(echo "$filtered_tests" | jq ".flaky_tests[$i]")
        add_test_to_template "$test_data"
    done
fi

add_test_to_template() {
    local flaky_test="$1"

    test_name=$(echo "$flaky_test" | jq -r '.test_name')
    classname=$(echo "$flaky_test" | jq -r '.classname')
    source=$(echo "$flaky_test" | jq -r '.source')
    times_flaked=$(echo "$flaky_test" | jq -r '.times_flaked')
    job_name=$(echo "$flaky_test" | jq -r '.job_name')
    job_number=$(echo "$flaky_test" | jq -r '.job_number')
    workflow_id=$(echo "$flaky_test" | jq -r '.workflow_id')
    workflow_created_at=$(echo "$flaky_test" | jq -r '.workflow_created_at')
    pipeline_number=$(echo "$flaky_test" | jq -r '.pipeline_number')

    if [ "$(datediff "${workflow_created_at}" today -f "%Y")" != '0' ]; then
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%Y years ago")
    elif [ "$(datediff "${workflow_created_at}" today -f "%m")" != '0' ]; then
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%m months ago")
    elif [ "$(datediff "${workflow_created_at}" today -f "%d")" != '0' ]; then
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%d days ago")
    elif [ "$(datediff "${workflow_created_at}" today -f "%H")" != '0' ]; then
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%H hours ago")
    elif [ "$(datediff "${workflow_created_at}" today -f "%M")" != '0' ]; then
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%M minutes ago")
    else
        last_flaked_message=$(datediff "${workflow_created_at}" today -f "%S seconds ago")
    fi

    if [ "$INCLUDE_TEST_INSIGHTS_LINK" = "true" ]; then
        test_url="https://app.circleci.com/pipelines/${PROJECT_SLUG}/${pipeline_number}/workflows/${workflow_id}/jobs/${job_number}/tests"
        last_flaked_field="*Last flaked:* <${test_url}|${last_flaked_message}>"
    else
        last_flaked_field="*Last flaked:* ${last_flaked_message}"
    fi

    flaky_test_template=$(cat << EOS
{
  "type": "divider"
},
{
  "type": "section",
  "text": {
    "type": "mrkdwn",
    "text": "*${test_name}*"
  }
},
{
  "type": "section",
  "fields": [
    {
      "type": "mrkdwn",
      "text": "*Classname:* ${classname}"
    },
    {
      "type": "mrkdwn",
      "text": "*Source:* ${source}"
    },
    {
      "type": "mrkdwn",
      "text": "*Job:* ${job_name}"
    },
    {
      "type": "mrkdwn",
      "text": "*Times flaked:* ${times_flaked}"
    },
    {
      "type": "mrkdwn",
      "text": "${last_flaked_field}"
    }
  ]
}
EOS
)
    template=$(echo "$template" | jq ".blocks |= . + [$flaky_test_template]")
}

export -f add_test_to_template

end_template=$(cat << EOS
{
  "type": "divider"
},
{
  "type": "actions",
  "elements": [
    {
      "type": "button",
      "text": {
        "type": "plain_text",
        "text": "Go to Insights Dashboard"
      },
      "url": "https://app.circleci.com/insights/${PROJECT_SLUG}",
      "style": "primary"
    }
  ]
}
EOS
)

template=$(echo "$template" | jq ".blocks |= . + [$end_template]")

if [ "${DEBUG}" = "true" ]; then
    echo "Debug: Generated Slack Template:"
    echo "$template" | jq '.'
fi

echo "$template" | jq > /tmp/SlackTemplateForFlakyTests.json
echo "export SLACK_TEMPLATE_FOR_FLAKY_TESTS=$(cat /tmp/SlackTemplateForFlakyTests.json)" >> "$BASH_ENV"

echo "Slack notification template created successfully."

make_api_call() {
    local url="$1"
    local attempt=1
    local response
    local http_code
    local body

    while [ $attempt -le "$MAX_RETRIES" ]; do
        if [ "${DEBUG}" = "true" ]; then
            echo "API call attempt $attempt/$MAX_RETRIES to: $url"
        fi

        response=$(curl -s -w "\n%{http_code}" --request GET \
            --url "$url" \
            --header "circle-token: $TOKEN")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [ "$http_code" = "200" ]; then
            echo "$body"
            return 0
        fi

        echo "API call failed with status code: $http_code" >&2

        if [ "$http_code" = "401" ]; then
            echo "Error: Authentication failed. Please check your CIRCLE_TOKEN." >&2
            exit 1
        elif [ "$http_code" = "404" ]; then
            echo "Error: Project not found. Please check your project slug: ${PROJECT_SLUG}" >&2
            exit 1
        fi

        if [ $attempt -lt "$MAX_RETRIES" ]; then
            echo "Retrying in ${RETRY_DELAY} seconds..." >&2
            sleep "$RETRY_DELAY"
        else
            echo "Failed after $MAX_RETRIES attempts" >&2
            echo "Response body: $body" >&2
            exit 1
        fi

        ((attempt++))
    done
}

echo "Fetching flaky tests data..."
api_url="https://circleci.com/api/v2/insights/${PROJECT_SLUG}/flaky-tests"
res=$(make_api_call "$api_url")

if [ "${DEBUG}" = "true" ]; then
    echo "Debug: Raw API Response:"
    echo "$res" | jq '.'
fi

if ! echo "$res" | jq . > /dev/null 2>&1; then
    echo "Error: Invalid JSON response from API"
    echo "Response: $res"
    exit 1
fi
