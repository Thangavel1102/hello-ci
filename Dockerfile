FROM ruby:3.3.10-slim

# Build tools for native gems, plus curl so we can test from inside the container
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libsqlite3-dev curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Corporate TLS is intercepted by Zscaler, so the container must trust its root CA
# or every https fetch (rubygems, apt over https) fails certificate verification.
COPY certs/zscaler.crt /usr/local/share/ca-certificates/zscaler.crt
RUN update-ca-certificates

WORKDIR /app

# Copy the gem manifests first so this layer is cached until dependencies change
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Now copy the application code
COPY . .

ENV RAILS_ENV=development

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
