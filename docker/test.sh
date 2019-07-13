#!/bin/sh
set -x

docker run --rm -it --name bash3-perl-test -v $PWD:/appspec bash3-perl prove -lrv t
