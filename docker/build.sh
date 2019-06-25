#!/bin/sh
DIR="$(dirname $0)"
cd "$DIR"
set -x
docker build -t bash3-perl .
