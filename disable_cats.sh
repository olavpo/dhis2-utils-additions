#!/bin/bash

# Define the IDS
IDS="pfAy2Crv2Fj,eDmkKeuRv4N,uYt28iYt7YV,r9Kye9XZUmC,GgFOdZmNoFm,yOyh7X30z2g,aRhr7BhMYTm,czTLAL4RKCA,zxBuVVUlXsg,f3v1Tv0JbyH,hxbbCuLXSMG,kDPYAC9RhU9,NhAa5fpVbeJ,rXcj5QYO07r,hY7vzwQ6mJO,y1oiL23YCE0,D4ux9xq4Lby,W0FqYHh9odL,yJVv9d8BaFQ,MghuTtZFCMf,mVCjbw3xDvC,LbFH2HZgv6I,ibNvPJLJvyj,ZglwuNCXEOh,oixCHB5APPr,UZk4nebX4Ft,l0pPQJA9YTs,ym1gkU6WTdy,YppcHwixHot,Y1Xg5ycjBMG,JgGDfIcDyiX,Uv9K6rELGLb,ohsbux1QFZ5,I6ZNqIGNiWw,Pitxm1ERmu5,DzBctyxKPAK,LEzxHvCLpKh,CukPzaTH9Oa,mJAF3PJPWzs,D5y7Aa0THSN"

# Convert IDS into an array
IFS=',' read -r -a id_array <<< "$IDS"

# Iterate over each ID and make CURL request
for ID in "${id_array[@]}"; do
  echo "Processing ID: $ID"
  
  curl "https://sandbox.hispghana.org/dhims/api/categories/$ID" \
  	-u 'Olav:xizbez-2vajgo-danFuc' \
    -X 'PATCH' \
    -H 'Content-Type: application/json-patch+json' \
    --data-raw '[{"op":"add","path":"/dataDimension","value":"false"}]'
  
  # Sleep for 3 seconds between requests
  sleep 3
done