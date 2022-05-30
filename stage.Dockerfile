# ================================
# Build image
# ================================
FROM swift:5.6-focal as build

# Install dependencies - do this before build for improved docker caching
# 1. libcurl4-openssl-dev needed for libcurl/ccurl commands in app
# 2. libssl-dev required by libcurl4-openssl-dev
# 3. cleanup after apt process
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
  && apt-get -q update \
  && apt-get -q dist-upgrade -y \
  && apt-get -q -y install \
  libcurl4-openssl-dev \
  libssl-dev \
  && rm -rf /var/lib/apt/lists/*

# Set /app as working directory
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve

# Copy everything from the build directory to docker's working directory
COPY . .

# Build everything, with optimizations
# -g enables debug info in compiled executable
# -Xswiftc passes flag through to all swift compiler invocations
# -c release => build with configuration release
RUN swift build -c release --static-swift-stdlib

# Switch to the staging area
WORKDIR /staging

# Copy main executable to staging area
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/Run" ./

# Copy resources bundled by SPM to staging area
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \;

# Copy any resouces from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# ================================
# Run image -- TODO: switch to focal-slim?
# ================================
FROM ubuntu:focal

# Make sure all system packages are up to date.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
  && apt-get -q update \
  && apt-get -q dist-upgrade -y \
  && apt-get -q install -y ca-certificates tzdata libxml2 libcurl4 \
  && rm -r /var/lib/apt/lists/*
    
# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Need to learn what these do
ARG env
ENV env ${env:-production}

# Sets working directory to /app
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "$env", "--hostname", "0.0.0.0", "--port", "8080", "--auto-migrate"]

# startup call
# $ docker-compose -f stage-docker-compose.yml up -d api nginx certbot