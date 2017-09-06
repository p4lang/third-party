# Shared Dockerfile for third party dependencies used in projects in the p4lang
# organization.
#
# Because multi-stage builds are relatively new and best practices aren't yet
# well established (as of this writing, at least), it's probably worth
# explaining the approach used in this Dockerfile. This Dockerfile creates a
# separate image for each third party dependency and then copies the binaries to
# a single output image at the end. If you add a new dependency, please:
#   (1) Create a new build image for it. (It should have its own FROM section.)
#   (2) Ensure that it installs everything that should be included in the final
#       image to `/output/usr/local`. Use DESTDIR and PYTHONUSERBASE for this.
#   (3) Use COPY to place the contents of the build image's `/output/usr/local`
#       in the final image.
#   (4) If the new dependency requires that certain apt packages be installed at
#       runtime (as opposed to at build time), create a new _DEPS variable and
#       install the new packages with all of the others; look at how the final
#       image is constructed and you'll understand the pattern.
# In general you don't have to worry about efficiency in the build images, but
# please minimize the amount of data and the number of layers that end up in the
# final image.

# Build our customized version of scapy.
FROM ubuntu:16.04 as scapy-vxlan
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV SCAPY_VXLAN_DEPS python python-setuptools
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./scapy-vxlan /scapy-vxlan/
WORKDIR /scapy-vxlan/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $SCAPY_VXLAN_DEPS
RUN python setup.py install --user

# Build PTF.
FROM ubuntu:16.04 as ptf
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV PTF_DEPS build-essential libpcap-dev python python-dev python-pip python-setuptools
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./ptf /ptf/
WORKDIR /ptf/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $PTF_DEPS
RUN pip install --user wheel
RUN pip install --user pypcap
RUN python setup.py install --user

# Build nanomsg.
FROM ubuntu:16.04 as nanomsg
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV NANOMSG_DEPS build-essential cmake
ENV CFLAGS="-Os"
ENV CXXFLAGS="-Os"
ENV LDFLAGS="-Wl,-s"
RUN mkdir /output
COPY ./nanomsg /nanomsg/
WORKDIR /nanomsg/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $NANOMSG_DEPS
RUN mkdir build
WORKDIR /nanomsg/build/
RUN cmake ..
RUN make DESTDIR=/output install

# Build nnpy.
FROM ubuntu:16.04 as nnpy
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV NNPY_DEPS build-essential libffi-dev python python-dev python-pip python-setuptools
ENV CFLAGS="-Os"
ENV CXXFLAGS="-Os"
ENV LDFLAGS="-Wl,-s"
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY --from=nanomsg /output/usr/local /usr/local/
COPY ./nnpy /nnpy/
WORKDIR /nnpy/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $NNPY_DEPS
RUN pip install --user wheel
RUN pip install --user cffi
RUN pip install --user .

# Build Thrift.
FROM ubuntu:16.04 as thrift
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV THRIFT_DEPS automake \
                bison \
                build-essential \
                flex \
                libboost-dev \
                libboost-test-dev \
                libevent-dev \
                libssl1.0.0 \
                libssl-dev \
                libtool \
                pkg-config \
                python \
                python-dev
ENV CFLAGS="-Os"
ENV CXXFLAGS="-Os"
ENV LDFLAGS="-Wl,-s"
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./thrift /thrift/
WORKDIR /thrift/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $THRIFT_DEPS
RUN ./bootstrap.sh
RUN ./configure --with-cpp=yes \
                --with-python=yes \
                --with-c_glib=no \
                --with-java=no \
                --with-ruby=no \
                --with-erlang=no \
                --with-go=no \
                --with-nodejs=no \
                --enable-tests=no
RUN make
RUN make DESTDIR=/output install-strip
WORKDIR /thrift/lib/py/
RUN python setup.py install --user

# Build Protocol Buffers.
# The protobuf build system normally downloads archives of GMock and GTest from
# Github, but the CA certs included with Ubuntu 14.04 are so old that the
# download fails TLS verification. It's just as well, because including the
# correct versions directly in the repo is preferable anyway. These versions
# are old, though, so they're walled off in the `protobuf-deps` directory. Our
# own projects should use a more recent release.
FROM ubuntu:16.04 as protobuf
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV PROTOCOL_BUFFERS_DEPS autoconf \
                          automake \
                          ca-certificates \
                          g++ \
                          libffi-dev \
                          libtool \
                          make \
                          python-dev \
                          python-setuptools
ENV CFLAGS="-Os"
ENV CXXFLAGS="-Os"
ENV LDFLAGS="-Wl,-s"
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./protobuf /protobuf/
COPY ./protobuf-deps/googlemock /protobuf/gmock
COPY ./protobuf-deps/googletest /protobuf/gmock/gtest
WORKDIR /protobuf/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $PROTOCOL_BUFFERS_DEPS
RUN ./autogen.sh
RUN ./configure
RUN make
RUN make DESTDIR=/output install-strip
WORKDIR /protobuf/python/
# We need to manually create this directory to work around a bug in protobuf's
# version of setup.py.
RUN mkdir -p /output/usr/local/lib/python2.7/site-packages
RUN python setup.py install --user --cpp_implementation

# Build gRPC.
# The gRPC build system should detect that a version of protobuf is already
# installed and should not try to install the third-party one included as a
# submodule in the grpc repository.
FROM ubuntu:16.04 as grpc
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV GRPC_DEPS autoconf \
              automake \
              build-essential \
              cython \
              libtool \
              python-dev \
              python-pip \
              python-setuptools
ENV LDFLAGS="-Wl,-s"
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY --from=protobuf /output/usr/local /usr/local/
COPY ./grpc /grpc/
WORKDIR /grpc/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $GRPC_DEPS
RUN make prefix=/output/usr/local
RUN make prefix=/output/usr/local install
RUN pip install --user -rrequirements.txt
RUN env GRPC_PYTHON_BUILD_WITH_CYTHON=1 pip install --user .

# Construct the final image.
FROM ubuntu:16.04
MAINTAINER Seth Fowler <sfowler@barefootnetworks.com>
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV SCAPY_VXLAN_RUNTIME_DEPS python-minimal
ENV PTF_RUNTIME_DEPS libpcap-dev python-minimal tcpdump
ENV NNPY_RUNTIME_DEPS python-minimal
ENV THRIFT_RUNTIME_DEPS libssl1.0.0 python-minimal
RUN apt-get update && \
    apt-get install -y --no-install-recommends $SCAPY_VXLAN_RUNTIME_DEPS \
                                               $PTF_RUNTIME_DEPS \
                                               $NNPY_RUNTIME_DEPS \
                                               $THRIFT_RUNTIME_DEPS
# pip install --user will place things in site-packages, but Ubuntu expects
# dist-packages by default, so we need to set PYTHONPATH.
ENV PYTHONPATH /usr/local/lib/python2.7/site-packages
COPY --from=scapy-vxlan /output/usr/local /usr/local/
COPY --from=ptf /output/usr/local /usr/local/
COPY --from=nanomsg /output/usr/local /usr/local/
COPY --from=nnpy /output/usr/local /usr/local/
COPY --from=thrift /output/usr/local /usr/local/
COPY --from=protobuf /output/usr/local /usr/local/
COPY --from=grpc /output/usr/local /usr/local/
RUN ldconfig
