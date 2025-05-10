#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 apache_logs [start_time] [end_time]"
    echo "Example: '17/May/2015:10:00' '17/May/2015:11:00'"
    exit 1
fi

LOGFILE=$1
START=${2:-""}
END=${3:-""}
TEMPFILE=$(mktemp)

if [[ -n "$START" && -n "$END" ]]; then
    awk -v start="$START" -v end="$END" '$0 ~ "\\[" && $0 ~ start, $0 ~ end' "$LOGFILE" > "$TEMPFILE"
else
    cp "$LOGFILE" "$TEMPFILE"
fi

echo "Log analysis for: $LOGFILE"
echo "Selected timeframe: ${START:-entire file} → ${END:-entire file}"
echo "==============================================================="

echo -e "\nRequest count:"
TOTAL=$(wc -l < "$TEMPFILE")
echo "$TOTAL"

echo -e "\nMethod usage (GET/POST):"
grep -oP '"\K(GET|POST)' "$TEMPFILE" | sort | uniq -c

echo -e "\nUnique IPs observed:"
awk '{print $1}' "$TEMPFILE" | sort | uniq | wc -l

echo -e "\nRequest breakdown per IP (GET & POST):"
awk '$6 ~ /"GET|POST/ {
    ip = $1
    method = gensub(/.*"(GET|POST).*/, "\\1", "g", $0)
    count[ip, method]++
}
END {
    printf "%-15s %-10s %-10s\n", "IP Address", "GET", "POST"
    for (key in count) {
        split(key, parts, SUBSEP)
        ip = parts[1]
        method = parts[2]
        data[ip][method] = count[key]
    }
    for (ip in data) {
        printf "%-15s %-10d %-10d\n", ip, data[ip]["GET"]+0, data[ip]["POST"]+0
    }
}' "$TEMPFILE" | sort -k2 -nr | head -20

echo -e "\nClient/server error responses:"
FAILURES=$(awk '{print $9}' "$TEMPFILE" | grep -E '^4|^5' | wc -l)
echo "$FAILURES"

PERCENT=$(awk -v f="$FAILURES" -v t="$TOTAL" 'BEGIN { printf "%.2f%%", (f/t)*100 }')
echo "Failure percentage: $PERCENT"

echo -e "\nTop requester (most active IP):"
awk '{print $1}' "$TEMPFILE" | sort | uniq -c | sort -nr | head -1

echo -e "\nAverage daily traffic:"
awk '{match($0, /\[([0-9]{2}\/[A-Za-z]+\/[0-9]{4})/, d); if(d[1]) print d[1]}' "$TEMPFILE" > /tmp/days.tmp
DAYS=$(sort /tmp/days.tmp | uniq | wc -l)
AVG=$(awk -v total="$TOTAL" -v days="$DAYS" 'BEGIN { printf "%.2f", total/days }')
echo "$AVG per day"

echo -e "\nDays with most errors:"
awk '$9 ~ /^[45]/ {match($0, /\[([0-9]{2}\/[A-Za-z]+\/[0-9]{4})/, d); if(d[1]) print d[1]}' "$TEMPFILE" | sort | uniq -c | sort -nr | head -5

echo -e "\nHourly request distribution:"
grep -oP '\[\K[0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9]{2}' "$TEMPFILE" | sort | uniq -c | sort > hourly_requests.csv
cat hourly_requests.csv

echo -e "\nDaily request count:"
sort /tmp/days.tmp | uniq -c | sort -nr > daily_requests.csv
cat daily_requests.csv

echo -e "\nHTTP status codes summary:"
awk '{print $9}' "$TEMPFILE" | grep -E '^[1-5][0-9][0-9]$' | sort | uniq -c | sort -nr > status_codes.csv
cat status_codes.csv

echo -e "\nMost frequent requesters per method:"
echo "GET:"
grep '"GET' "$TEMPFILE" | awk '{print $1}' | sort | uniq -c | sort -nr | head -5
echo "POST:"
grep '"POST' "$TEMPFILE" | awk '{print $1}' | sort | uniq -c | sort -nr | head -5

echo -e "\nError frequency (day/hour):"
awk '$9 ~ /^[45]/ {
    match($0, /\[([0-9]{2}\/[A-Za-z]+\/[0-9]{4}):([0-9]{2})/, t);
    if (t[1] && t[2]) {
        print t[1] "," t[2]
    }
}' "$TEMPFILE" | sort | uniq -c | awk '{print $2","$3","$1}' > failures_by_day_hour.csv
cat failures_by_day_hour.csv

rm "$TEMPFILE" /tmp/days.tmp 2>/dev/null
