FROM bash:3

RUN apk update \
    && apk add \
    perl \
    perl-test-harness-utils \
    perl-app-cpanminus \
    make \
    wget \
    perl-dev \
    musl-dev \
    && cpanm -n YAML::PP App::Spec
