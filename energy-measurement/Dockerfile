FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        libprotobuf-dev \
        protobuf-compiler \
        libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . /project
WORKDIR /project

RUN mkdir -p /builds && ln -sfn /project/examples /builds/examples

