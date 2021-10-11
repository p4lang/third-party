![Docker build](https://github.com/p4lang/third-party/workflows/Build%20and%20push%20latest%20image/badge.svg?branch=main&event=push)

This repository contains third-party dependencies of the software in p4lang. It
can be used to install these dependencies on your machine, but it's primarily
intended for use in automation. The provided Dockerfile is suitable for usage as
a base for generating Docker images for other p4lang repos.

Please see the Dockerfile for the canonical installation instructions.

This repository includes Google Protocol Buffers. The version we use depends on
old releases of GTest and GMock, which are located in in `protobuf-deps`. These
releases are out-of-date and are not suitable for use in p4lang projects; please
use a current release for new work.
