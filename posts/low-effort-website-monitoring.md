While the most lazy website monitoring implementation would be probably to check
it in `cron` with `curl` every few minutes and send message on outage, I'm going
to present a slightly more sophisticated solution to make it a little more
usable. Note that idea below probably isn't be the best for long term, but
often any solution is better than no solution at all.

# Requirements

By operator I mean person responsible for service reliability. Ideally that
would be someone involved in website development or hosting maintainer.

> **Protip**: Notifications are the most effective when receiver knows how to
  react on them.

- Operator must be notified on outage.
- Monitoring must not rely on website hosting availability. I'm talking about
  single node deployments here. Operator must be informed not only when check
  failed, but also when check wasn't performed.
- Monitoring must provide reason for notification. Messages like *It's not
  working* aren't very insightful.
- Implementation must be simple, lightweight and cheap. Preferably allowing
  self-hosting and open-source.

# Incremental development

Let's assume that we're dealing with website hosted on a cheap GNU/Linux VPS
instance that consists of application exposed via HTTPS. It makes
sense to check liveness at minimum. For now we don't care, if our application
performs well. Availability is our only concern.

## Basic HTTP service check with notification

To keep things simple and increase reliability we will keep service checking and
reporting/notifying logic separately.

- *Service checking* - Since shell is usually available out-of-the-box we will
  build service checks using widely available command line tools.
- *Reporting/notifying* - This is a bit harder. Keep in mind that we need
  notifications also when service checking hasn't finished on time. Hosting
  anything on the same instance as application will not be sufficient. Using
  external service might introduce vendor lock-in, but we want it cheap.
  Fortunately there's some middle ground like
  [Healthchecks](https://healthchecks.io) - an open source monitoring platform,
  also hosted as a service with free subscription tier.

Using *Healthchecks* means that we will need to notify external service about
service check results. `curl` will do the job here. Let's start with some
minimal script:

```
#!/usr/bin/env bash

CURL_OPTIONS="--max-time 5 --retry 3 --fail --silent --show-error"
SERVICE_URL=https://app.local/
HEALTCHECK_URL=https://hc-ping.com/82583301-bd04-4028-9695-fc5473abc15d

curl $CURL_OPTIONS "$SERVICE_URL"
curl $CURL_OPTIONS "${HEALTCHECK_URL}/${?}"
```

Above script will send it's status code in ping to *Healthchecks*, where we
should configure notifications(Telegram integration works well) and **Schedule** -
it's crucial to receive alert when our service is not sending any pings, it
may mean that whole VPS is down. Yet we still don't have context what exactly
went wrong. Let's use [Bash strict
mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/) and change
script to send `curl` error text in ping:

```
#!/usr/bin/env bash

set -euo pipefail

CURL_OPTIONS="--max-time 5 --retry 3 --fail --silent --show-error"
SERVICE_URL=https://app.local/
HEALTCHECK_URL=https://hc-ping.com/82583301-bd04-4028-9695-fc5473abc15d
RESULT=""

on_exit() {
	curl $CURL_OPTIONS --data-raw "$RESULT" "${HEALTCHECK_URL}/${?}" >/dev/null
}

main () {
	trap on_exit EXIT
	RESULT=$(curl $CURL_OPTIONS "$SERVICE_URL" 2>&1 1>/dev/null)
}

main "$@"
```

Now operator will be notified about possible outages and alert will include some
context what exactly went wrong like:

```
curl: (7) Failed to connect to app.local port 443: Connection refused
```

## Service is available, but does it perform well?

While performance can be measured in many ways, we will focus on one simple
metric: *response time*. `curl` can measure it out-of-the-box, but we will need
to invoke it differently and format output message:

```
# on_exit version supporting custom EXIT_CODE
on_exit() {
	local exit_code=$?
	if [ -n "$EXIT_CODE" ]; then
		exit_code=$EXIT_CODE
	fi
	curl $CURL_OPTIONS --data-raw "$RESULT" "${HEALTCHECK_URL}/${exit_code}" >/dev/null
	exit "$exit_code"
}

# Alert, if curl failed or response takes longer than 2 seconds
CHECK_HTTP_TIMEOUT=2
main () {
	trap on_exit EXIT
	RESULT="Response time: $(curl $CURL_OPTIONS "$SERVICE_URL" -o /dev/null --write-out '%{time_total}' 2>&1)"
	local time_total
	time_total=$(echo "$RESULT" | rev | cut -d ' ' -f 1 | rev)
	echo "$time_total"
	if [ "$(echo "${time_total} > ${CHECK_HTTP_TIMEOUT}" | bc)" -eq 1 ]; then
		RESULT="${RESULT}"$'\n'"Too high response time!"
		EXIT_CODE=1
	fi
}
```

## What about other metrics?

*Healthchecks* limits us to 10 kilobytes payload for each ping, but remember
that we want to keep it simple, so it's not much of a problem. Rearranging our
script into self-descriptive functions will be useful to include more checks:

```
# Trigger alert when used memory exceeds 95%
CHECK_MEMORY_THRESHOLD=95
check_memory() {
	RESULT="${RESULT}"$'\n'"Memory usage: $(exec 2>&1; free | grep Mem | awk '{print $3/$2 * 100.0}')"
	local used
	used=$(echo "$RESULT" | tail -n 1 | rev | cut -d ' ' -f 1 | rev)
	if [ "$(echo "${used} > ${CHECK_MEMORY_THRESHOLD}" | bc)" -eq 1 ]; then
		RESULT="${RESULT}"$'\n'"Too high memory usage!"
		EXIT_CODE=1
	fi
}

main () {
	trap on_exit EXIT
	check_http
	check_memory
}
```

Observing SSL expiration date can be enclosed in single Bash function as well:

```
CHECK_SSL_DAYS=90
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
```

# Conclusion

It took us ~100 lines of Bash to check:

- Service availability via HTTP
- Service response time
- Service SSL certificate expiration date
- Instance memory usage

We can run this script every minute from cron:

```
* * * * * /opt/low-effort-monitoring.sh
```

Of course it's not the most beautiful and performance oriented way of monitoring
website, but it serves the purpose. No special software nor planning is required
here, so it may be a great ad-hoc solution while you plan long term monitoring
system like Icinga2, Prometheus or Zabbix.

Full script can be found [here](/media/low-effort-monitoring.sh).
