#!/bin/zsh
set -euo pipefail

LOG="$HOME/Library/Logs/ynab-convert.log"
exec >>"$LOG" 2>&1

echo "[$(date)] starting: $*"

export PATH="/Users/kvasbo/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:$PATH"
cd /Users/kvasbo/Git/ynab
exec /Users/kvasbo/.rbenv/shims/bundle exec /Users/kvasbo/.rbenv/shims/ruby bin/convert "$@"
