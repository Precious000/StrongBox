
#!/bin/bash

# HTTP request parsing and response helpers



http_respond() {

local status="$1" body="$2" ctype="${3:-application/json}"

local text

case $status in

200) text="OK" ;; 201) text="Created" ;; 204) text="No Content" ;;

400) text="Bad Request" ;; 401) text="Unauthorized" ;;

403) text="Forbidden" ;; 404) text="Not Found" ;;

409) text="Conflict" ;; 503) text="Service Unavailable" ;;

*) text="Internal Server Error"; status=500 ;;

esac

local len=${#body}

printf "HTTP/1.1 %s %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s" \
"$status" "$text" "$ctype" "$len" "$body"

}



http_parse() {

HTTP_METHOD="" HTTP_PATH="" HTTP_QUERY="" HTTP_BODY="" HTTP_TOKEN=""

local first=true cl=0



while IFS= read -r line; do

line="${line%$'\r'}"

if $first; then

HTTP_METHOD=$(echo "$line" | awk '{print $1}')

local fp

fp=$(echo "$line" | awk '{print $2}')

HTTP_PATH="${fp%%\?*}"

HTTP_QUERY="${fp#*\?}"

[[ "$HTTP_PATH" == "$fp" ]] && HTTP_QUERY=""

first=false

continue

fi

[[ -z "$line" ]] && {

[[ $cl -gt 0 ]] && HTTP_BODY=$(dd bs=1 count=$cl 2>/dev/null)

break

}

local hn hv

hn=$(echo "$line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')

hv=$(echo "$line" | cut -d: -f2- | sed 's/^ //')

case "$hn" in

"content-length") cl=$hv ;;

"authorization") HTTP_TOKEN="${hv#Bearer }" ;;

esac

done

}



http_json() {

local json="$1" field="$2"

echo "$json" | python3 -c \
"import sys,json; print(json.loads(sys.stdin.read()).get('$field',''))" 2>/dev/null

}

