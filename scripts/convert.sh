#!/usr/bin/env bash
# Convert every Sigma rule into one query file per backend:
#   build/sentinel/<rule>.kql      (Microsoft Sentinel / KQL)
#   build/wazuh/<rule>.lucene      (Wazuh indexer / OpenSearch Lucene)
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build && mkdir -p build/sentinel build/wazuh
fail=0
for rule in $(find rules -name '*.yml' | sort); do
  name=$(basename "$rule" .yml)
  if ! sigma convert -t kusto -p pipelines/sentinel.yml "$rule" > "build/sentinel/$name.kql" 2> "build/sentinel/$name.err"; then
    echo "FAIL sentinel  $rule"; cat "build/sentinel/$name.err"; fail=1
  fi
  if ! sigma convert -t opensearch_lucene -p pipelines/wazuh.yml "$rule" > "build/wazuh/$name.lucene" 2> "build/wazuh/$name.err"; then
    echo "FAIL wazuh     $rule"; cat "build/wazuh/$name.err"; fail=1
  fi
  rm -f "build/sentinel/$name.err" "build/wazuh/$name.err"
  echo "ok   $rule"
done
exit $fail
