################################################################################
# Build Stage
################################################################################
FROM elixir:1.19-otp-28-alpine AS build

ENV MIX_ENV=prod \
    LANG=en_US.UTF-8 \
    ERL_FLAGS="+JPperf true"

# Install build dependencies
RUN apk add --no-cache build-base git ca-certificates openssl curl

WORKDIR /app

# Install hex and rebar (cached layer)
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy only dependency-related files first for better caching
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/

# Fetch and compile dependencies (cached if mix.lock unchanged)
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy the rest of the application
COPY config/runtime.exs config/
COPY lib ./lib

# Compile the application
RUN mix compile --warnings-as-errors

# Build the release
RUN mix release

################################################################################
# Runtime Stage
################################################################################
FROM alpine:3.23 AS runtime

ENV MIX_ENV=prod \
    LANG=en_US.UTF-8 \
    PHX_SERVER=true \
    PORT=443 \
    # Erlang runtime settings
    ERL_AFLAGS="-kernel shell_history enabled"

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc \
    curl \
    ca-certificates && \
    update-ca-certificates

# Create non-root user for security
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/sh -D app

# Create SSL directory and generate self-signed cert
RUN mkdir -p /etc/ssl/private && \
    openssl req -x509 -nodes -subj "/CN=localhost" -days 3650 -newkey rsa:2048 \
      -keyout /etc/ssl/private/selfsigned.key \
      -out /etc/ssl/certs/selfsigned.crt && \
    chown app:app /etc/ssl/private/selfsigned.key

WORKDIR /app

# Copy the release from build stage
COPY --from=build --chown=app:app /app/_build/prod/rel/backend ./

# Switch to non-root user
USER app

# Expose HTTPS port
EXPOSE 443

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -kf https://localhost:443/healthz || exit 1

# Run the release
CMD ["bin/backend", "start"]


