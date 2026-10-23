#!/bin/sh
# The project's ONE build (AGENTS.md: compile-th3.ps1 is the ONLY build).
# No new build logic here - this only calls it.
# No server, no browser preview: the product is an MT4 indicator, it runs inside
# the terminal the user opens, not in a page.
set -e
cd "$(dirname "$0")"
powershell -NoProfile -ExecutionPolicy Bypass -File compile-th3.ps1 -Project all
