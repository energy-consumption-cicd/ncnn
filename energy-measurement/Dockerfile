# The job runs on ubuntu-20.04: the ubuntu:20.04 image current at the tag commit (2024-08-20) and the archive of that date.
FROM ubuntu:focal-20240530@sha256:fa17826afb526a9fc7250e0fbcbfd18d03fe7a54849472f86879d8bf562c629e

ARG APT_SNAPSHOT=20240820T002356Z

ENV DEBIAN_FRONTEND=noninteractive

# ca-certificates comes from the current archive only to reach the snapshot service over https.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    sed -i "s#http://archive.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}/#; s#http://security.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}/#" \
        /etc/apt/sources.list && \
    grep -q "snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}/" /etc/apt/sources.list && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        libprotobuf-dev \
        protobuf-compiler \
        libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

# Toolchain versions of the archive at the tag commit; a rebuild that resolves others fails here.
RUN test "$(dpkg-query -W -f='${Version}' gcc-9)" = "9.4.0-1ubuntu1~20.04.2" && \
    test "$(dpkg-query -W -f='${Version}' cmake)" = "3.16.3-1ubuntu1.20.04.1" && \
    test "$(dpkg-query -W -f='${Version}' libprotobuf-dev)" = "3.6.1.3-2ubuntu5.2" && \
    test "$(dpkg-query -W -f='${Version}' libopencv-dev)" = "4.2.0+dfsg-5"

COPY . /project
WORKDIR /project

RUN mkdir -p /builds && ln -sfn /project/examples /builds/examples
