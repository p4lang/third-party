FROM ubuntu:14.04
MAINTAINER Seth Fowler <seth.fowler@barefootnetworks.com>

ENV DEBIAN_FRONTEND noninteractive

# Default to using 2 make jobs, which is a good default for CI. If you're
# building locally or you know there are more cores available, you may want to
# override this.
ARG MAKEFLAGS
ENV MAKEFLAGS ${MAKEFLAGS:-j2}

# Build nanomsg.
# We use `-DCMAKE_INSTALL_PREFIX=/usr` because on Ubuntu 14.04 the library is
# installed in /usr/local/lib/x86_64-linux-gnu/ by default, and for some reason
# ldconfig cannot find it.
ENV NANOMSG_DEPS build-essential cmake
COPY ./nanomsg /nanomsg/
WORKDIR /nanomsg/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $NANOMSG_DEPS && \
    mkdir build && \
    cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr && \
    cmake --build . && \
    cmake --build . --target install && \
    apt-get purge -y $NANOMSG_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /nanomsg /var/cache/apt/* /var/lib/apt/lists/*

# Build nnpy.
ENV NNPY_DEPS build-essential libffi-dev python-dev python-pip
ENV NNPY_RUNTIME_DEPS python
COPY ./nnpy /nnpy/
WORKDIR /nnpy/
RUN apt-get update && \
    apt-get install -y --no-install-recommends $NNPY_DEPS $NNPY_RUNTIME_DEPS && \
    pip install cffi && \
    pip install . && \
    apt-get purge -y $NNPY_DEPS && \
    apt-get autoremove --purge -y && \
    rm -rf /nnpy /var/cache/apt/* /var/lib/apt/lists/*

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
    rm -rf /thrift /var/cache/apt/* /var/lib/apt/lists/*
