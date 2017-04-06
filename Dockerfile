FROM ubuntu:16.04
MAINTAINER Seth Fowler <seth.fowler@barefootnetworks.com>

ENV DEBIAN_FRONTEND noninteractive

# Default to using 2 make jobs, which is a good default for CI. If you're
# building locally or you know there are more cores available, you may want to
# override this.
ARG MAKEFLAGS
ENV MAKEFLAGS ${MAKEFLAGS:-j2}

# Build nanomsg.
ENV NANOMSG_DEPS build-essential cmake
COPY ./nanomsg /nanomsg/
WORKDIR /nanomsg/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $NANOMSG_DEPS && \
    mkdir build && \
    cd build && \
    export CFLAGS="-Os" && \
    export CXXFLAGS="-Os" && \
    export LDFLAGS="-Wl,-s" && \
    cmake .. && \
    cmake --build . && \
    cmake --build . --target install && \
    apt-get purge -y $NANOMSG_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /nanomsg /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/* /var/lib/dpkg/*-old /var/log/*

# Build nnpy.
ENV NNPY_DEPS build-essential libffi-dev python-dev python-pip python-setuptools
ENV NNPY_RUNTIME_DEPS python
COPY ./nnpy /nnpy/
WORKDIR /nnpy/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $NNPY_DEPS $NNPY_RUNTIME_DEPS && \
    export CFLAGS="-Os" && \
    export CXXFLAGS="-Os" && \
    export LDFLAGS="-Wl,-s" && \
    pip install wheel && \
    pip install cffi && \
    pip install . && \
    apt-get purge -y $NNPY_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /nnpy /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/* /var/lib/dpkg/*-old /var/log/*

# Build Thrift.
ENV THRIFT_DEPS automake \
                bison \
                build-essential \
                flex \
                libboost-dev \
                libboost-test-dev \
                libevent-dev \
                libssl-dev \
                libtool \
                pkg-config \
                python-dev
ENV THRIFT_RUNTIME_DEPS libssl1.0.0 python
COPY ./thrift /thrift/
WORKDIR /thrift/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $THRIFT_DEPS $THRIFT_RUNTIME_DEPS && \
    export CFLAGS="-Os" && \
    export CXXFLAGS="-Os" && \
    export LDFLAGS="-Wl,-s" && \
    ./bootstrap.sh && \
    ./configure --with-cpp=yes \
                --with-python=yes \
                --with-c_glib=no \
                --with-java=no \
                --with-ruby=no \
                --with-erlang=no \
                --with-go=no \
                --with-nodejs=no && \
    make && \
    make install && \
    cd lib/py && \
    python setup.py install && \
    apt-get purge -y $THRIFT_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /thrift /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/* /var/lib/dpkg/*-old /var/log/*

# Build Protocol Buffers.
# The protobuf build system normally downloads archives of GMock and GTest from
# Github, but the CA certs included with Ubuntu 14.04 are so old that the
# download fails TLS verification. It's just as well, because including the
# correct versions directly in the repo is preferable anyway. These versions
# are old, though, so they're walled off in the `protobuf-deps` directory. Our
# own projects should use a more recent release.
ENV PROTOCOL_BUFFERS_DEPS autoconf \
                          automake \
                          g++ \
                          libtool \
                          make
COPY ./protobuf /protobuf/
COPY ./protobuf-deps/googlemock /protobuf/gmock
COPY ./protobuf-deps/googletest /protobuf/gmock/gtest
WORKDIR /protobuf/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $PROTOCOL_BUFFERS_DEPS && \
    export CFLAGS="-Os" && \
    export CXXFLAGS="-Os" && \
    export LDFLAGS="-Wl,-s" && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    ldconfig && \
    apt-get purge -y $PROTOCOL_BUFFERS_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /protobuf /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/* /var/lib/dpkg/*-old /var/log/*

# Build gRPC.
# The gRPC build system should detect that a version of protobuf is already
# installed and should not try to install the third-party one included as a
# submodule in the grpc repository.
ENV GRPC_DEPS build-essential \
              autoconf \
              libtool
COPY ./grpc /grpc/
WORKDIR /grpc/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $GRPC_DEPS && \
    export LDFLAGS="-Wl,-s" && \
    make && \
    make install && \
    ldconfig && \
    apt-get purge -y $GRPC_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /grpc /var/cache/apt/* /var/lib/apt/lists/* /var/cache/debconf/* /var/lib/dpkg/*-old /var/log/*
