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
# In general you don't have to worry about efficiency in the build images, but
# please minimize the amount of data and the number of layers that end up in the
# final image.

# Build ccache.
FROM ubuntu:16.04 as ccache
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV CCACHE_DEPS autoconf automake build-essential libmemcached-dev
ENV CFLAGS="-Os"
ENV CXXFLAGS="-Os"
ENV LDFLAGS="-Wl,-s"
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./ccache /ccache/
WORKDIR /ccache/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $CCACHE_DEPS
# Tell the ccache build system not to bother with things like documentation.
ENV RUN_FROM_BUILD_FARM=yes
RUN ./autogen.sh
RUN ./configure --enable-memcached
RUN make
# `make install` assumes that we *did* build the docs; make it happy.
RUN touch ccache.1
RUN make DESTDIR=/output install

# Build our customized version of scapy.
FROM ubuntu:16.04 as scapy-vxlan
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV SCAPY_VXLAN_DEPS python python-pip python-setuptools
RUN mkdir -p /output/usr/local
ENV PYTHONUSERBASE=/output/usr/local
COPY ./scapy-vxlan /scapy-vxlan/
WORKDIR /scapy-vxlan/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $SCAPY_VXLAN_DEPS
RUN pip install --user --ignore-installed wheel
RUN pip install --user --ignore-installed .

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
RUN pip install --user --ignore-installed wheel
RUN pip install --user --ignore-installed pypcap
RUN pip install --user --ignore-installed .

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
RUN pip install --user --ignore-installed wheel
RUN pip install --user --ignore-installed cffi
RUN pip install --user --ignore-installed .

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
                python-dev \
                python-pip \
                python-setuptools
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
RUN pip install --user --ignore-installed .

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
# We'll finish up the process of building protobuf below, but first, a bit of
# explanation.
#
# Since we can't use `pip` with protobuf's `setup.py`, the package gets
# installed via setuptools in an "egg" - a directory which acts as a python
# module, but isn't a package and thus isn't automatically part of the package
# namespace. Eggs need their contents to be added to python's `sys.path` to
# become visible. Hooks that run early during python startup normally read
# `setuptools.pth` and other `.pth` files and add all of the directories
# referenced in those files to the path; egg contents are placed in those files
# to be made available to the rest of the python installation.
#
# In multistage builds this doesn't work so well, because those `.pth` files can
# easily be overwritten by other versions from a different image, and the eggs
# we're installing here will no longer appear in `sys.path`. To work around
# that, we just copy the contents of the existing `.pth` files into a new one
# with a name we're sure won't be overwritten. Python will read this new `.pth`
# file at startup and include the eggs in the path.
#
# If you're wondering why the `grep -v` is necessary, meditate upon the fact
# that these files aren't merely metadata but also executable code, and
# setuptools, by design, uses this feature to inject code into every python
# program that runs on your system.
WORKDIR /output/usr/local/lib/python2.7/site-packages
RUN cat *.pth | grep -v "import sys" | sort -u > docker_protobuf.pth

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
RUN ldconfig
COPY ./grpc /grpc/
WORKDIR /grpc/
RUN apt-get update
RUN apt-get install -y --no-install-recommends $GRPC_DEPS
RUN make prefix=/output/usr/local
RUN make prefix=/output/usr/local install
# We don't use `--ignore-installed` here because otherwise we won't use the
# installed version of the protobuf python package that we copied from the
# protobuf build image.
RUN pip install --user -rrequirements.txt
RUN env GRPC_PYTHON_BUILD_WITH_CYTHON=1 pip install --user --ignore-installed .

# Construct the final image.
FROM ubuntu:16.04
MAINTAINER Seth Fowler <sfowler@barefootnetworks.com>
ARG DEBIAN_FRONTEND=noninteractive
ARG MAKEFLAGS=-j2
ENV CCACHE_RUNTIME_DEPS libmemcached-dev
ENV SCAPY_VXLAN_RUNTIME_DEPS python-minimal
ENV PTF_RUNTIME_DEPS libpcap-dev python-minimal tcpdump
ENV NNPY_RUNTIME_DEPS python-minimal
ENV THRIFT_RUNTIME_DEPS libssl1.0.0 python-minimal
ENV GRPC_RUNTIME_DEPS python-minimal python-setuptools
RUN apt-get update && \
    apt-get install -y --no-install-recommends $CCACHE_RUNTIME_DEPS \
                                               $SCAPY_VXLAN_RUNTIME_DEPS \
                                               $PTF_RUNTIME_DEPS \
                                               $NNPY_RUNTIME_DEPS \
                                               $THRIFT_RUNTIME_DEPS \
                                               $GRPC_RUNTIME_DEPS && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*
# Configure ccache so that descendant containers won't need to.
ENV CCACHE_MEMCACHED_ONLY=true
ENV CCACHE_MEMCACHED_CONF=--SERVER=ccache
ENV CCACHE_COMPILERCHECK=content
ENV CCACHE_CPP2=true
ENV CCACHE_COMPRESS=true
ENV CCACHE_MAXSIZE=1G
# Copy files from the build containers.
COPY --from=ccache /output/usr/local /usr/local/
COPY --from=scapy-vxlan /output/usr/local /usr/local/
COPY --from=ptf /output/usr/local /usr/local/
COPY --from=nanomsg /output/usr/local /usr/local/
COPY --from=nnpy /output/usr/local /usr/local/
COPY --from=thrift /output/usr/local /usr/local/
COPY --from=protobuf /output/usr/local /usr/local/
COPY --from=grpc /output/usr/local /usr/local/
# `pip install --user` will place things in `site-packages`, but Ubuntu expects
# `dist-packages` by default, so we need to set configure `site-packages` as an
# additional "site-specific directory".
RUN echo "import site; site.addsitedir('/usr/local/lib/python2.7/site-packages')" \
        > /usr/local/lib/python2.7/dist-packages/use_site_packages.pth
RUN ldconfig
