#!/bin/bash

curl -d '{"url":"https://s3.amazonaws.com/cdn-origin-etr.akc.org/wp-content/uploads/2017/11/16105011/English-Cocker-Spaniel-Slide03.jpg"}' \
    -H "Content-Type: application/json" \
    -X POST https://a4840wg9e9.execute-api.eu-west-1.amazonaws.com/Prod/invocations/
