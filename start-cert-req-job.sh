#!/bin/bash
set -eu

bundle install --path vendor/bundler
bundle exec ruby cert_req_job.rb -e=production --cert_req_interval=43200
