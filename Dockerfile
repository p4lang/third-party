# Shared Dockerfile for third party dependencies used in projects in the p4lang
# organization.
#
# Best practices for multi-stage builds are available at
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
#
# The approach used in this Dockerfile is as follows:
#
# A multi-stage build creates a separate image for each third party dependency and
# then copies only the binaries to a single output image at the end.
#
# If you add a new dependency, please:
#   (1) Create a new build image for it. (It should have its own FROM section.)
#   (2) Ensure that it installs everything that should be included in the final
#       image to `/output/usr/local`. Use DESTDIR and PYTHONUSERBASE for this.
#       Be sure to install python packages and code using
#       `pip install --user --ignore-installed`. If you absolutely *must* use
#       `python setup.py install`, take a look at the protobuf build image and
#       then reconsider.
#   (3) Use COPY to place the contents of the build image's `/output/usr/local`
#       in the final image.
#   (4) If the new dependency requires that certain apt packages be installed at
#       runtime (as opposed to at build time), create a new _DEPS variable and
#       install the new packages with all of the others; look at how the final
#       image is constructed and you'll understand the pattern.
#
# In general you don't have to worry about the size of intermediate build images,
# but please minimize the amount of data and the number of layers that end up in the
# final image.

# Create an image with tools used as a base for the next layers
FROM ubuntu:24.04 AS base-builder
ARG MAKEFLAGS=-j2
ENV DEBIAN_FRONTEND=noninteractive \
    CFLAGS="-Os" \
    CXXFLAGS="-Os" \
    LDFLAGS="-Wl,-s" \
    LD_LIBRARY_PATH=/output/usr/local/lib/
RUN apt-get update -qq && apt-get install -qq --no-install-recommends \
        autoconf \
        automake \
        bison \
        build-essential \
        ca-certificates \
        cmake \
        flex \
        g++ \
        git \
        libavl-dev \
        libboost-dev \
        libboost-test-dev \
        libev-dev \
        libevent-dev \
        libffi-dev \
        libmemcached-dev \
        libpcap-dev \
        libpcre3-dev \
        libprotobuf-c-dev \
        libtool \
        make \
        pkg-config \
        protobuf-c-compiler \
        python3 \
        python3-dev \
        python3-venv && \
    ldconfig && \
    mkdir -p /output/usr/local && \
    python3 -m venv /output/usr/local

# Build ccache.
FROM base-builder AS ccache
ENV RUN_FROM_BUILD_FARM=yes
# Tell the ccache build system not to bother with things like documentation.
RUN cd / && \
    git clone https://github.com/WebHare/ccache && \
    cd ccache && \
    git checkout 969cd90dc998eb4b197f15544ee0dee95f96a946 && \
    ./autogen.sh && \
    ./configure --enable-memcached && \
    make && \
# `make install` assumes that we *did* build the docs; make it happy.
    touch ccache.1  && \
    make DESTDIR=/output install

# Build PTF.
FROM base-builder AS ptf
WORKDIR /
SHELL ["/bin/bash", "-c"]
RUN cd / && \
    git clone https://github.com/p4lang/ptf && \
    cd ptf && \
    git checkout 8e0fdf8b214422ea6db6c6b41042160b9be2d8c3 && \
    source /output/usr/local/bin/activate && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install wheel && \
    python3 -m pip install . && \
    python3 -m pip install scapy==2.5.0

# Build nanomsg.
FROM base-builder AS nanomsg
WORKDIR /
RUN cd / && \
    git clone https://github.com/nanomsg/nanomsg && \
    cd nanomsg && \
    git checkout 096998834451219ee7813d8977f6a4027b0ccb43 && \
    mkdir -p /nanomsg/build && \
    cd /nanomsg/build && \
    cmake .. && \
    make DESTDIR=/output install

# Build nnpy.
FROM base-builder AS nnpy
COPY --from=nanomsg /output/usr/local /usr/local/
WORKDIR /
SHELL ["/bin/bash", "-c"]
RUN cd / && \
    git clone https://github.com/nanomsg/nnpy && \
    cd nnpy && \
    git checkout 1.4.2 && \
    source /output/usr/local/bin/activate && \
    ldconfig && \
    python3 -m pip install wheel cffi && \
    python3 -m pip install .

# Build Thrift.
FROM base-builder AS thrift
WORKDIR /
SHELL ["/bin/bash", "-c"]
RUN cd / && \
    git clone https://github.com/apache/thrift && \
    cd thrift && \
    git checkout v0.16.0 && \
    source /output/usr/local/bin/activate && \
    ./bootstrap.sh && \
    ./configure \
        --with-cpp=yes \
        --with-python=no \
        --with-c_glib=no \
        --with-java=no \
        --with-ruby=no \
        --with-erlang=no \
        --with-go=no \
        --with-nodejs=no \
        --enable-tests=no && \
    make && \
    make DESTDIR=/output install-strip && \
    python3 -m pip install thrift==0.16.0

# Build Protocol Buffers.
FROM base-builder AS protobuf
WORKDIR /
SHELL ["/bin/bash", "-c"]
RUN mkdir -p /build && \
    cd /build && \
    git clone https://github.com/google/protobuf && \
    cd protobuf && \
    git checkout v5.26.1 && \
    git submodule update --init --recursive
RUN cd /build/protobuf && \
    cmake -Dprotobuf_BUILD_SHARED_LIBS=ON . && \
    make -j$(nproc)
RUN cd /build/protobuf && \
    make DESTDIR=/output install && \
    source /output/usr/local/bin/activate && \
    python3 -m pip install protobuf==5.26.1

# Build gRPC
FROM base-builder AS grpc
COPY --from=protobuf /output/usr/local /usr/local/
RUN ldconfig
WORKDIR /
SHELL ["/bin/bash", "-c"]
RUN cd / && \
    git clone https://github.com/grpc/grpc && \
    cd grpc && \
    git checkout v1.64.3 && \
    git submodule update --init --recursive
RUN cd /grpc && \
    mkdir -p cmake/build && \
    cd cmake/build && \
    cmake ../.. \
      -DgRPC_INSTALL=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DgRPC_PROTOBUF_PROVIDER=package \
      -DgRPC_SSL_PROVIDER=module && \
    make DESTDIR=/output install && \
    ldconfig && \
    source /output/usr/local/bin/activate && \
    python3 -m pip install grpcio==1.64.3

# Build libyang
FROM base-builder AS libyang
WORKDIR /
RUN cd / && \
    git clone https://github.com/CESNET/libyang && \
    cd libyang && \
    git checkout 8e690c2a98275494ee06e37bb1cc26d19f3c4c5e && \
    mkdir -p /libyang/build/
WORKDIR /libyang/build/
RUN cmake .. && \
    make DESTDIR=/output install

# Build sysrepo
FROM base-builder AS sysrepo
COPY --from=libyang /output/usr/local /usr/local/
RUN ldconfig
WORKDIR /
RUN cd / && \
    git clone https://github.com/sysrepo/sysrepo && \
    cd sysrepo && \
    git checkout v0.7.5 && \
    mkdir -p /sysrepo/build/
WORKDIR /sysrepo/build/
# CALL_TARGET_BINS_DIRECTLY=Off is needed here because of the use of DESTDIR
# Without it sysrepoctl is executed at install time and assumes YANG files are
# under /etc/sysrepo/yang
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_EXAMPLES=Off -DCALL_TARGET_BINS_DIRECTLY=Off .. && \
    make DESTDIR=/output install

# Construct the final image.
FROM ubuntu:24.04
LABEL maintainer="P4 Developers <p4-dev@lists.p4.org>"
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
RUN CCACHE_RUNTIME_DEPS="libmemcached-dev" && \
    PTF_RUNTIME_DEPS="libpcap-dev python3-minimal tcpdump" && \
    NNPY_RUNTIME_DEPS="python3-minimal" && \
    THRIFT_RUNTIME_DEPS="python3-minimal" && \
    GRPC_RUNTIME_DEPS="libssl-dev python3-minimal python3-setuptools libre2-dev" && \
    SYSREPO_RUNTIME_DEPS="libpcre3 libavl1 libev4 libprotobuf-c1" && \
    apt-get update && \
    apt-get install -y --no-install-recommends $CCACHE_RUNTIME_DEPS \
                                               $PTF_RUNTIME_DEPS \
                                               $NNPY_RUNTIME_DEPS \
                                               $THRIFT_RUNTIME_DEPS \
                                               $GRPC_RUNTIME_DEPS \
                                               $SYSREPO_RUNTIME_DEPS && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*
# Configure ccache so that descendant containers won't need to.
COPY ./docker/ccache.conf /usr/local/etc/ccache.conf
# Copy files from the build containers.
COPY --from=ccache /output/usr/local /usr/local/
COPY --from=ptf /output/usr/local /usr/local/
COPY --from=nanomsg /output/usr/local /usr/local/
COPY --from=nnpy /output/usr/local /usr/local/
COPY --from=thrift /output/usr/local /usr/local/
COPY --from=protobuf /output/usr/local /usr/local/
COPY --from=grpc /output/usr/local /usr/local/
COPY --from=libyang /output/usr/local /usr/local/
COPY --from=sysrepo /output/usr/local /usr/local/
COPY --from=sysrepo /output/etc /etc/
# `pip install --user` will place things in `site-packages`, but Ubuntu expects
# `dist-packages` by default, so we need to set configure `site-packages` as an
# additional "site-specific directory".
RUN export PYTHON3_VERSION=`python3 -c 'import sys; version=sys.version_info[:3]; print("python{0}.{1}".format(*version))'` && \
  echo "import site; site.addsitedir('/usr/local/lib/$PYTHON3_VERSION/site-packages')" \
    > /usr/local/lib/$PYTHON3_VERSION/dist-packages/use_site_packages.pth

RUN ldconfig
