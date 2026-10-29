#!/bin/zsh
# Wrapper for api_health_check.py to ensure cron has the correct PATH and
# working directory. Logs are written by cron from the crontab entry.

export PATH="/usr/local/bin:/usr/bin:/bin:/Library/Frameworks/Python.framework/Versions/3.12/bin:$PATH"
cd /Users/smehta/Desktop/Dev/kraken/thing-finder || exit 1

exec /Users/smehta/Desktop/Dev/kraken/thing-finder/scripts/api_health_check.py
