#!/usr/bin/env bash
################################################################################
# Copyright (c) 2021 Jakub Pieńkowski
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
################################################################################

set -euo pipefail

CURL_OPTIONS="--max-time 5 --retry 3 --fail --silent --show-error"
SERVICE_URL=https://github.com.com/
HEALTCHECK_URL=https://hc-ping.com/82583301-bd04-4028-9695-fc5473abc15d
RESULT=""
EXIT_CODE=""

CHECK_HTTP_TIMEOUT=2
CHECK_MEMORY_THRESHOLD=95
CHECK_SSL_DAYS=30

on_exit() {
	local exit_code=$?
	if [ -n "$EXIT_CODE" ]; then
		exit_code=$EXIT_CODE
	fi
	curl $CURL_OPTIONS --data-raw "$RESULT" "${HEALTCHECK_URL}/${exit_code}" >/dev/null
	exit "$exit_code"
}

check_http() {
	RESULT="${RESULT}"$'\n'"Response time: $(curl $CURL_OPTIONS "$SERVICE_URL" -o /dev/null --write-out '%{time_total}' 2>&1)"
	local time_total
	time_total=$(echo "$RESULT" | tail -n 1 | rev | cut -d ' ' -f 1 | rev)
	if [ "$(echo "${time_total} > ${CHECK_HTTP_TIMEOUT}" | bc)" -eq 1 ]; then
		RESULT="${RESULT}"$'\n'"Too high response time!"
		EXIT_CODE=1
	fi
}

check_memory() {
	RESULT="${RESULT}"$'\n'"Memory usage: $(exec 2>&1; free | grep Mem | awk '{print $3/$2 * 100.0}')"
	local used
	used=$(echo "$RESULT" | tail -n 1 | rev | cut -d ' ' -f 1 | rev)
	if [ "$(echo "${used} > ${CHECK_MEMORY_THRESHOLD}" | bc)" -eq 1 ]; then
		RESULT="${RESULT}"$'\n'"Too high memory usage!"
		EXIT_CODE=1
	fi
}

check_ssl() {
	local host
	host=$(echo "$SERVICE_URL" | cut -d '/' -f 3)
	RESULT="${RESULT}"$'\n'"SSL certificate expiration date: $(
		exec 2>&1; echo |
			openssl s_client -servername "$host" -connect "${host}:443" 2>/dev/null |
			openssl x509 -noout -enddate |
			cut -d '=' -f 2
	)"
	local end_seconds
	end_seconds=$(("$CHECK_SSL_DAYS" * 24 * 60 * 60))
	if ! echo |
			openssl s_client -servername "$host" -connect "${host}:443" 2>/dev/null |
			openssl x509 -noout -checkend "$end_seconds" >/dev/null; then
		RESULT="${RESULT}"$'\n'"Certificate will expire soon!"
		EXIT_CODE=1
	fi
}

main () {
	trap on_exit EXIT
	check_ssl
	check_memory
	check_http
}

main "$@"
