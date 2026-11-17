FROM node:22-bookworm-slim AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY scripts/build-demo.mjs scripts/build-demo.mjs
RUN npm run build

FROM ruby:3.3.13-slim-bookworm AS gems
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libssl-dev pkg-config && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY lib/ lib/
COPY omniauth-whop.gemspec ./
COPY deploy/Gemfile deploy/Gemfile.lock deploy/
ENV BUNDLE_GEMFILE=/app/deploy/Gemfile BUNDLE_FROZEN=true
RUN bundle install && rm -rf /usr/local/bundle/cache

FROM ruby:3.3.13-slim-bookworm
WORKDIR /app
ENV BUNDLE_GEMFILE=/app/deploy/Gemfile BUNDLE_FROZEN=true RACK_ENV=production
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=gems /app /app
COPY examples/ examples/
COPY --from=assets /app/examples/public/ examples/public/
RUN useradd --uid 10001 --create-home demo
USER demo
EXPOSE 9292
CMD ["bundle", "exec", "puma", "--bind", "tcp://0.0.0.0:9292", "--threads", "1:5", "examples/config.ru"]
