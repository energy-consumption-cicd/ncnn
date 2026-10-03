# ubuntu-latest of the tag commit (2025-09-15) is 24.04: the ubuntu:24.04 image and the archive of that date.
FROM ubuntu:noble-20250805@sha256:9cbed754112939e914291337b5e554b07ad7c392491dba6daf25eef1332a22e8

ARG APT_SNAPSHOT=20250915T074259Z

ENV DEBIAN_FRONTEND=noninteractive

# ca-certificates comes from the current archive only to reach the snapshot service over https.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    sed -i "s#http://archive.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}/#; s#http://security.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT}/#" \
        /etc/apt/sources.list.d/ubuntu.sources && \
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
RUN test "$(dpkg-query -W -f='${Version}' gcc-13)" = "13.3.0-6ubuntu2~24.04" && \
    test "$(dpkg-query -W -f='${Version}' cmake)" = "3.28.3-1build7" && \
    test "$(dpkg-query -W -f='${Version}' libprotobuf-dev)" = "3.21.12-8.2ubuntu0.2" && \
    test "$(dpkg-query -W -f='${Version}' libopencv-dev)" = "4.6.0+dfsg-13.1ubuntu1"

COPY . /project
WORKDIR /project

RUN mkdir -p /builds && ln -sfn /project/examples /builds/examples

