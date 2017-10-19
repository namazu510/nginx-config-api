#!/bin/bash
set -eu

bundle install --path vendor/bundler
bundle exec ruby main.rb -e production -o 0.0.0.0
