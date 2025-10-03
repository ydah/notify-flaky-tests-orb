# Flaky Tests Notify Orb

[![CircleCI Build Status](https://circleci.com/gh/ydah/notify-flaky-tests-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/ydah/notify-flaky-tests-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/ydah/notify-flaky-tests.svg)](https://circleci.com/orbs/registry/orb/ydah/notify-flaky-tests) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/ydah/notify-flaky-tests-orb/master/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

A CircleCI Orb that detects and notifies flaky tests in your project, helping you identify and fix unstable tests quickly.

## Prerequisites

Before using this orb, you need to set up the following environment variables:

1. CIRCLE_TOKEN: A CircleCI API token (v2) for accessing Test Insights
   - [How to generate CircleCI API token](https://circleci.com/docs/managing-api-tokens)
2. SLACK_ACCESS_TOKEN: A Slack OAuth token for posting messages
   - [Slack Orb Setup Guide](https://github.com/CircleCI-Public/slack-orb/wiki/Setup)
3. SLACK_DEFAULT_CHANNEL: Default Slack channel for notifications

## Installation

The orb uses shell scripts internally with minimal dependencies (jq and dateutils) that are automatically installed. The CircleCI executor (`cimg/base`) includes all necessary base tools.

## Usage

### Basic Usage

```yaml
version: 2.1

orbs:
  notify-flaky-tests: ydah/notify-flaky-tests@2.0.0

workflows:
  notify_flaky_tests:
    jobs:
      - notify-flaky-tests/notify
```

### Scheduled Pipeline (Recommended)

Use [Scheduled Pipelines](https://circleci.com/docs/scheduled-pipelines) to run periodic checks:

```yaml
version: 2.1

orbs:
  notify-flaky-tests: ydah/notify-flaky-tests@2.0.0

parameters:
  notify_flaky_tests:
    type: boolean
    default: false

workflows:
  notify_flaky_tests:
    when: << pipeline.parameters.notify_flaky_tests >>
    jobs:
      - notify-flaky-tests/notify:
          channel: "#qa-team"
```

### Advanced Configuration

```yaml
version: 2.1

orbs:
  notify-flaky-tests: ydah/notify-flaky-tests@2.0.0

workflows:
  nightly_flaky_test_report:
    triggers:
      - schedule:
          cron: "0 2 * * *"
          filters:
            branches:
              only:
                - main
    jobs:
      - notify-flaky-tests/notify:
          project_slug: gh/ydah/my-project
          channel: "#qa-team,#dev-team"
          time_range: 30
          minimum_flake_count: 3
          test_file_pattern: ".*spec\\.js$"
          notification_title: ":rotating_light: Critical Flaky Tests Report"
          include_statistics: true
          debug: true
          output_metrics: true
          metrics_format: json
```

### Using as a Command

```yaml
version: 2.1

orbs:
  notify-flaky-tests: ydah/notify-flaky-tests@2.0.0

jobs:
  custom_notify:
    executor: notify-flaky-tests/default
    steps:
      - checkout
      - notify-flaky-tests/notify:
          project_slug: << pipeline.project.git_url >>
          channel: "#engineering"
          minimum_flake_count: 5
      - run:
          name: Process metrics
          command: |
            if [ -f /tmp/flaky_tests_metrics.json ]; then
              cat /tmp/flaky_tests_metrics.json
            fi

workflows:
  custom_workflow:
    jobs:
      - custom_notify
```

## Parameters

### Job/Command Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `project_slug` | string | (current project) | Project slug in the form `vcs-slug/org-name/repo-name` |
| `channel` | string | `$SLACK_DEFAULT_CHANNEL` | Slack channel(s) to notify (comma-separated) |
| `circle_token` | string | `$CIRCLE_TOKEN` | CircleCI API token |
| `time_range` | integer | `90` | Time range for fetching flaky tests (in days) |
| `minimum_flake_count` | integer | `1` | Minimum number of flakes to include |
| `test_file_pattern` | string | `""` | Regex pattern to filter test files |
| `notification_title` | string | `:warning: Flaky tests detected` | Custom Slack notification title |
| `include_statistics` | boolean | `true` | Include statistics in the notification |
| `include_test_insights_link` | boolean | `true` | Include links to test insights |
| `group_by_class` | boolean | `false` | Group tests by class name |
| `debug` | boolean | `false` | Enable debug mode |
| `output_metrics` | boolean | `false` | Output metrics to file |
| `metrics_format` | enum | `json` | Format for metrics (json, csv, prometheus) |
| `max_retries` | integer | `3` | Maximum API retry attempts |
| `retry_delay` | integer | `5` | Delay between retries (seconds) |

## Output Examples

### Slack Notification

The orb sends a structured Slack message with:
- Summary of flaky tests count
- Detailed information for each test:
  - Test name and class
  - Source file location
  - Number of times flaked
  - Last flake occurrence with link
- Statistical summary (if enabled)
- Link to CircleCI Insights dashboard

### Metrics Output

When `output_metrics` is enabled, the orb generates metrics in your specified format:

#### JSON Format
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "project": "gh/ydah/my-project",
  "total_flaky_tests": 5,
  "tests": [
    {
      "name": "test_example",
      "classname": "ExampleTest",
      "source": "test/example_spec.js",
      "times_flaked": 3,
      "job_name": "test",
      "last_flaked": "2024-01-14T15:20:00Z"
    }
  ]
}
```

#### CSV Format
```csv
timestamp,project,test_name,classname,source,times_flaked,job_name,last_flaked
2024-01-15T10:30:00Z,gh/ydah/my-project,test_example,ExampleTest,test/example_spec.js,3,test,2024-01-14T15:20:00Z
```

#### Prometheus Format
```
# HELP circleci_flaky_tests_total Total number of flaky tests
# TYPE circleci_flaky_tests_total gauge
circleci_flaky_tests_total{project="gh/ydah/my-project"} 5

# HELP circleci_flaky_test_flakes Number of times each test has flaked
# TYPE circleci_flaky_test_flakes gauge
circleci_flaky_test_flakes{project="gh/ydah/my-project",test="test_example",class="ExampleTest",job="test"} 3
```

## Troubleshooting

### Enable Debug Mode

Set `debug: true` to get detailed logs:

```yaml
- notify-flaky-tests/notify:
    debug: true
```

### Common Issues

1. Authentication Failed: Check your `CIRCLE_TOKEN` is valid and has proper permissions
2. Project Not Found: Verify the `project_slug` format (e.g., `gh/owner/repo`)
3. No Slack Notification: Ensure `SLACK_ACCESS_TOKEN` and channel permissions are correct
4. No Flaky Tests Found: This is good! The job will halt gracefully
5. API Rate Limiting: Adjust `max_retries` and `retry_delay` parameters if needed

## Development

### Local Testing with Docker

Test the orb scripts locally using Docker Compose:

```bash
# Set required environment variables
export CIRCLE_TOKEN=your_token
export SLACK_ACCESS_TOKEN=your_slack_token

# Run tests
make docker-test

# Run linters
make docker-lint
```

### Make Commands

The project includes a Makefile with helpful commands:

```bash
make help              # Show all available commands
make validate          # Validate orb configuration
make lint              # Run all linters (shellcheck + yamllint)
make test              # Run all tests and validations
make pack              # Pack the orb from source
make publish-dev       # Publish development version
make clean             # Clean generated files
```

## Resources

- [CircleCI Orb Registry Page](https://circleci.com/orbs/registry/orb/ydah/notify-flaky-tests)
- [CircleCI Test Insights Documentation](https://circleci.com/docs/insights-tests)
- [CircleCI Orb Documentation](https://circleci.com/docs/2.0/orb-intro)
- [Slack Orb Setup Guide](https://github.com/CircleCI-Public/slack-orb/wiki/Setup)

## Contributing

We welcome [issues](https://github.com/ydah/notify-flaky-tests-orb/issues) and [pull requests](https://github.com/ydah/notify-flaky-tests-orb/pulls)!

## Publishing Updates

1. Merge changes to the main branch
2. Create a new [semantically versioned](http://semver.org/) release on GitHub
3. The publishing pipeline will automatically deploy the new version

## License

MIT License - see [LICENSE](LICENSE) file for details

## Author

Created and maintained by [ydah](https://github.com/ydah)
