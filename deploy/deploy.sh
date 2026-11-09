#!/usr/bin/env bash
# Deploy the demo stack to dedic. Run from the repository root on the Mac:
#   deploy/deploy.sh [service...]
# Secrets come from the `secret` store and go to the remote shell on stdin,
# so they are not written to disk or to the remote process list.
set -euo pipefail
HOST=${HOST:-dedic}
DIR=/opt/cube-demo

rsync -az --delete deploy/docker-compose.yml deploy/clickhouse "$HOST:$DIR/"
rsync -az --delete seed/ "$HOST:$DIR/seed/"
rsync -az --delete model/ "$HOST:$DIR/model/"

secret run --mask \
  CH_ADMIN_PASSWORD=CUBE_CLOUD_DEMO_CH_ADMIN_PASSWORD \
  CH_CUBE_PASSWORD=CUBE_CLOUD_DEMO_CH_CUBE_PASSWORD \
  CUBEJS_API_SECRET=CUBE_CLOUD_DEMO_CUBEJS_API_SECRET -- \
  sh -c 'printf "export CH_ADMIN_PASSWORD=%s CH_CUBE_PASSWORD=%s CUBEJS_API_SECRET=%s\n" \
           "$CH_ADMIN_PASSWORD" "$CH_CUBE_PASSWORD" "$CUBEJS_API_SECRET" \
         | ssh "$0" "cd $1 && . /dev/stdin && docker compose up -d --remove-orphans ${2:-}"' \
  "$HOST" "$DIR" "$*"
