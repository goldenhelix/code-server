#
# Node Build Image
#
FROM debian:bookworm-20241202-slim AS nodebuilder
RUN apt-get update && apt-get install -y xz-utils openssl jq curl python3 build-essential
#COPY node-binary.tar.xz /opt/node-binary.tar.xz
RUN curl -L https://nodejs.org/dist/v24.18.1/node-v24.18.1-linux-x64.tar.xz -o /opt/node-binary.tar.xz
RUN mkdir -p /opt/node
RUN tar -xvf  /opt/node-binary.tar.xz --strip-components=1 -C /opt/node/
ENV PATH="/opt/node/bin:${PATH}"

#
# Native Module Rebuild Image
#
# `npm run release` compiles VS Code's native modules on the build host, so they link
# against the host's glibc. @parcel/watcher and @vscode/sqlite3 end up requiring
# GLIBC_2.38, which the bookworm (glibc 2.36) main image does not have -- the recursive
# file watcher dies with "[IPC Library: File Watcher] Uncaught Exception: ... GLIBC_2.38
# not found" and the sqlite binding cannot be loaded. Rebuild those two here, from the
# npm source tarballs of the exact versions shipped in release-standalone, against
# bookworm's glibc and the same Node 24 headers.
#
FROM nodebuilder AS nativebuilder
COPY ./release-standalone/lib/vscode/node_modules/@parcel/watcher/package.json /opt/native/watcher.json
COPY ./release-standalone/lib/vscode/node_modules/@vscode/sqlite3/package.json /opt/native/sqlite3.json
RUN set -e; cd /opt/native \
   && npm install --ignore-scripts --omit=dev --omit=optional --no-audit --no-fund \
      "@parcel/watcher@$(node -p "require('./watcher.json').version")" \
      "@vscode/sqlite3@$(node -p "require('./sqlite3.json').version")" \
   && for m in @parcel/watcher @vscode/sqlite3; do \
        (cd node_modules/$m && node /opt/node/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild --nodedir=/opt/node); \
      done

# Main image
FROM debian:bookworm-20241202-slim

USER root

LABEL description="Golden Helix Code Server"

# Backend
COPY --from=nodebuilder /opt/node /opt/node

# OpenTOFU
# Install openssl for prisma and other standard packages we want available
RUN apt-get update \
   && apt-get install -y openssl openssh-client iputils-ping curl wget jq rsync nano lsof vim tree traceroute less unzip \
      zlib1g libbz2-1.0 liblzma5 libcurl4 libssl3 libcurl3-gnutls libdeflate0 libncurses6 zstd rclone pigz htop aria2 ripgrep \
      procps git git-lfs \
   && apt-get clean

RUN wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64.tar.gz -O - | \
   tar xz && mv yq_linux_amd64 /usr/bin/yq

# Python 3.10 and add to path
RUN curl -L https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-3.10.15+20241016-x86_64_v2-unknown-linux-gnu-install_only.tar.gz -o /opt/python-3.10.tar.gz \
   && tar -xvf /opt/python-3.10.tar.gz -C /opt/ \
   && rm /opt/python-3.10.tar.gz \
   && /opt/python/bin/pip3 install --no-cache-dir requests ipykernel miniwdl Jinja2

# Update paths
ENV PATH="${PATH}:/opt/node/bin:/opt/python/bin"
ENV PYTHONPATH="/opt/apiserver"
ENV SYS_DATA_PATH="/opt/apiserver/Data/"
RUN echo "export PATH=\$PATH:/opt/node/bin:/opt/python/bin" >> /etc/bash.bashrc

# Install various locales to support users from different regions
COPY ./install_locales.sh /tmp/install_locales.sh
RUN bash /tmp/install_locales.sh

# Copy the release-standalone directory
COPY ./release-standalone /opt/code-server
COPY ./startup.sh /opt/code-server/startup.sh

# Replace the two native modules that were linked against the build host's newer glibc (see nativebuilder)
COPY --from=nativebuilder /opt/native/node_modules/@parcel/watcher/build/Release/watcher.node /opt/code-server/lib/vscode/node_modules/@parcel/watcher/build/Release/watcher.node
COPY --from=nativebuilder /opt/native/node_modules/@vscode/sqlite3/build/Release/vscode-sqlite3.node /opt/code-server/lib/vscode/node_modules/@vscode/sqlite3/build/Release/vscode-sqlite3.node

# Remove the existing node binary and create symlink to the system node
RUN rm -f /opt/code-server/lib/node && \
    ln -s /opt/node/bin/node /opt/code-server/lib/node && \
    chmod +x /opt/code-server/startup.sh

# ms-python.debugpy and ms-toolsai.jupyter write into their own extension directory at
# runtime (debug adapter endpoint files, IPyWidgets staging). /opt/code-server is root-owned,
# so pre-create exactly those directories for the runtime user (uid 1000) instead of making
# the extension code writable. Globs survive version bumps.
RUN set -e; \
    for d in /opt/code-server/lib/vscode/extensions/ms-python.debugpy-*/; do \
        if [ -f "$d/package.json" ]; then install -d -o 1000 -g 1000 -m 755 "$d/.noConfigDebugAdapterEndpoints"; fi; \
    done; \
    for d in /opt/code-server/lib/vscode/extensions/ms-toolsai.jupyter-2*/; do \
        if [ -f "$d/package.json" ]; then install -d -o 1000 -g 1000 -m 755 "$d/temp"; fi; \
    done

# Set the environment variables
ARG LANG='en_US.UTF-8'
ARG LANGUAGE='en_US:en'
ARG LC_ALL='en_US.UTF-8'
ARG START_XFCE4=1
ARG TZ='Etc/UTC'
ENV HOME=/home/ghuser \
    SHELL=/bin/bash \
    USERNAME=ghuser \
    LANG=$LANG \
    LANGUAGE=$LANGUAGE \
    LC_ALL=$LC_ALL \
    TZ=$TZ \
    AUTH_USER=ghuser \
    CODE_SERVER_SESSION_SOCKET=/home/ghuser/.config/code-server/code-server-ipc.sock \
    PASSWORD=ghuserpassword \
    PORT=8080

RUN useradd -m -u 1000 -s /bin/bash ghuser

### Ports and user
EXPOSE $PORT
WORKDIR $HOME
USER 1000

RUN mkdir -p $HOME/.config/code-server && \
echo "bind-addr: 0.0.0.0:8080" > $HOME/.config/code-server/config.yaml && \
echo "auth: password" >> $HOME/.config/code-server/config.yaml && \
echo "password: \${PASSWORD}" >> $HOME/.config/code-server/config.yaml && \
echo "cert: true" >> $HOME/.config/code-server/config.yaml


RUN mkdir -p $HOME/Workspace/Documents

ENTRYPOINT ["/opt/code-server/startup.sh"]
