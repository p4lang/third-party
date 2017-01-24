FROM ubuntu:14.04
MAINTAINER Seth Fowler <seth.fowler@barefootnetworks.com>

# Install dependencies.
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get install -y \
      automake \
      bison \
      build-essential \
      cmake \
      flex \
      git \
      libboost-dev \
      libboost-test-dev \
      libevent-dev \
      libffi-dev \
      libssl-dev \
      libtool \
      pkg-config \
      python-dev \
      python-pip

# Default to using 8 make jobs, which is appropriate for local builds. On CI
# infrastructure it will often be best to override this.
ARG MAKEFLAGS
ENV MAKEFLAGS ${MAKEFLAGS:-j8}

# Build nanomsg.
# We use `-DCMAKE_INSTALL_PREFIX=/usr` because on Ubuntu 14.04 the library is
# installed in /usr/local/lib/x86_64-linux-gnu/ by default, and for some reason
# ldconfig cannot find it.
COPY ./nanomsg /third-party/nanomsg/
WORKDIR /third-party/nanomsg/
RUN mkdir build && \
    cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr && \
    cmake --build . && \
    cmake --build . --target install

# Build nnpy.
COPY ./nnpy /third-party/nnpy/
WORKDIR /third-party/nnpy/
RUN pip install cffi && \
    pip install .

# Build Thrift.
COPY ./thrift /third-party/thrift/
WORKDIR /third-party/thrift/
RUN ./bootstrap.sh && \
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
    python setup.py install
