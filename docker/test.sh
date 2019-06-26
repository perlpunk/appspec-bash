#!/bin/sh
set -x

docker run -it -v $PWD:/appspec bash3-perl prove -lrv t
