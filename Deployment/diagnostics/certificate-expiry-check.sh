#!/bin/sh
set -eu
certificate=/etc/letsencrypt/live/178.105.32.46/fullchain.pem
if ! /usr/bin/openssl x509 -checkend 172800 -noout -in "$certificate"; then
  /usr/bin/logger -p authpriv.err -t universalassistant-certificate "IP certificate expires in less than 48 hours"
  exit 1
fi
