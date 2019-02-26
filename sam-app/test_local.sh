#!/bin/bash

curl -d '{"url":"https://s3.amazonaws.com/cdn-origin-etr.akc.org/wp-content/uploads/2017/11/16105011/English-Cocker-Spaniel-Slide03.jpg"}' \
    -H "Content-Type: application/json" \
    -X POST http://127.0.0.1:3000/invocations
