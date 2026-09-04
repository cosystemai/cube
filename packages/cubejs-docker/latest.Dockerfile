FROM node:24.20.0-trixie-slim AS builder

WORKDIR /cube
COPY . .

RUN yarn policies set-version v1.22.22
# Yarn v1 uses aggressive timeouts with summing time spending on fs, https://github.com/yarnpkg/yarn/issues/4890
RUN yarn config set network-timeout 120000 -g

# Required for node-oracledb to buld on ARM64
RUN apt-get update \
    && apt-get upgrade -y \
    # libpython3-dev is needed to trigger post-installer to download native with python
    && apt-get install -y python3.13 libpython3.13-dev gcc g++ make cmake ca-certificates \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1 \
    && rm -rf /var/lib/apt/lists/*

# We are copying root yarn.lock file to the context folder during the Publish GH
# action. So, a process will use the root lock file here.
RUN yarn install --prod \
    # Remove DuckDB sources to reduce image size
    && rm -rf /cube/node_modules/duckdb/src \
    && yarn cache clean

FROM node:24.20.0-trixie-slim

ARG IMAGE_VERSION=unknown

ENV CUBEJS_DOCKER_IMAGE_VERSION=$IMAGE_VERSION
ENV CUBEJS_DOCKER_IMAGE_TAG=latest

# The runtime stage installs the *runtime* Python library, not the `-dev` one.
# `@cubejs-backend/native` links `libpython3.13.so.1.0` — the SONAME shipped by
# `libpython3.13` — so the only things `libpython3.13-dev` added here were the
# unversioned `.so` link-editor symlink and `libpython3.13.a`, neither of which
# a running container resolves. It also dragged in `libc6-dev` and with it
# `linux-libc-dev`, i.e. the Linux kernel headers, whose several hundred
# mostly-unfixable kernel CVEs dominated this image's scan report while being
# unreachable from a container that never compiles anything.
RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libssl3t64 python3.13 libpython3.13 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1 \
    && rm -rf /var/lib/apt/lists/*

RUN yarn policies set-version v1.22.22

ENV NODE_ENV=production
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR /cube

COPY --from=builder /cube .

# By default Node dont search in parent directory from /cube/conf, @todo Reaserch a little bit more
ENV NODE_PATH=/cube/conf/node_modules:/cube/node_modules
ENV PYTHONUNBUFFERED=1
RUN ln -s /cube/node_modules/.bin/cubejs /usr/local/bin/cubejs
RUN ln -s /cube/node_modules/.bin/cubestore-dev /usr/local/bin/cubestore-dev

WORKDIR /cube/conf

EXPOSE 4000

CMD ["cubejs", "server"]
