#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 ENDPOINT_URL. Must provide an endpoint URL to call."
    exit 1
fi

ENDPOINT_URL=$1
IMAGE_URL=${2:-"https://s3.amazonaws.com/cdn-origin-etr.akc.org/wp-content/uploads/2017/11/16105011/English-Cocker-Spaniel-Slide03.jpg"}

echo "Endpoint URL is ${ENDPOINT_URL} and Image URL is ${IMAGE_URL}"

curl -d "{\"url\":\"${IMAGE_URL}\"}" \
    -H "Content-Type: application/json" \
    -X POST ${ENDPOINT_URL}
