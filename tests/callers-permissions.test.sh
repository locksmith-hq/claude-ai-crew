#!/usr/bin/env bash
# A reusable workflow can only use the permissions its caller grants; if it asks for more, GitHub rejects the run
# with a startup failure. Check every caller template grants at least what its reusable workflow requests.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
command -v ruby >/dev/null 2>&1 || { echo "callers-permissions.test: ruby missing, skipped"; exit 0; }
ruby -ryaml -e '
LEVEL = {"none"=>0, "read"=>1, "write"=>2}
map = {"crew-wake"=>"wake","crew-review"=>"review","crew-change-sync"=>"change-sync","crew-owner-alert"=>"owner-alert",
       "crew-schedule-worker"=>"role-run","crew-schedule-lead"=>"role-run","crew-schedule-pm"=>"role-run"}
pass = fail = 0
map.each do |caller, reusable|
  cy = YAML.safe_load(File.read("templates/callers/#{caller}.yml").gsub(/<[A-Z_]+>/, "x/y"), aliases: true)
  ry = YAML.safe_load(File.read(".github/workflows/#{reusable}.yml"), aliases: true)
  need = {}
  ([ry["permissions"]] + ry["jobs"].values.map { |j| j["permissions"] }).compact.each do |h|
    h.each { |k, v| need[k] = v if LEVEL[v] > (LEVEL[need[k]] || -1) }
  end
  cj = cy["jobs"].values.first
  have = cj["permissions"] || cy["permissions"] || {}
  missing = need.select { |k, v| LEVEL[have[k] || "none"] < LEVEL[v] }
  if missing.empty? then pass += 1; puts "ok   #{caller} grants what #{reusable}.yml needs"
  else fail += 1; puts "FAIL #{caller} lacks #{missing.inspect} that #{reusable}.yml requests" end
end
puts "callers-permissions.test: #{pass} passed, #{fail} failed"
exit(fail.zero? ? 0 : 1)'
