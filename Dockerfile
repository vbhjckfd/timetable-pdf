# Pinned to alpine 3.18: the wkhtmltopdf binary below was built in 2019 against
# OpenSSL 1.1 and dies with "Error relocating /bin/wkhtmltopdf: SSL_CTX_free:
# symbol not found" on any newer alpine. 3.18 is the last one packaging
# openssl1.1-compat.

# Build stage: compile native gems, then strip Ruby down to what the server runs.
FROM ruby:3.1-alpine3.18 AS build

RUN apk add --no-cache build-base font-dejavu

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4

# Compiled extensions are already copied into lib/, so sources, objects and gem
# caches go; so do Ruby's headers, static lib, docs and the dev-only bundled gems.
RUN cd /usr/local/bundle \
 && rm -rf cache gems/*/ext gems/*/spec gems/*/test gems/*/docs gems/*/example* \
 && find . \( -name '*.o' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name 'Makefile' -o -name 'mkmf.log' -o -name 'gem_make.out' \) -delete \
 && rm -rf /usr/local/include /usr/local/share /usr/local/lib/*.a /usr/local/lib/pkgconfig \
 && cd /usr/local/lib/ruby/gems/3.1.0 \
 && rm -rf cache doc \
 && for g in debug irb minitest power_assert rake rbs rdoc reline readline test-unit typeprof net-ftp net-imap net-pop net-smtp rss rinda prime matrix; do \
      rm -rf gems/$g-[0-9]* specifications/$g-[0-9]*.gemspec; \
    done

# Runtime stage: bare Alpine, Ruby's runtime libs, and what wkhtmltopdf links.
FROM alpine:3.18

RUN apk add --no-cache \
    gmp libffi libgcc libstdc++ yaml zlib ca-certificates \
    libx11 libxrender fontconfig openssl1.1-compat

# Every drawing brings its own fonts as @font-face, so a system font is only a
# fallback; fontconfig resolves every family the SVGs name to DejaVu Sans.
COPY --from=build /usr/share/fonts/dejavu/DejaVuSans.ttf /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf /usr/share/fonts/dejavu/

COPY --from=build /usr/local /usr/local

# On alpine static compiled patched qt headless wkhtmltopdf (46.8 MB).
# Compilation took place in Travis CI (job 606718795) with auto push to Docker
# Hub. The checksum used to be read back from that job's log at build time;
# api.travis-ci.org no longer exists, so the tag is pinned to its digest and
# the expected checksum is recorded here instead.
COPY --from=madnight/alpine-wkhtmltopdf-builder:0.12.5-alpine3.10-606718795@sha256:009bc5a3e8823b92568473f075e157b59488d0ddf3209865a7aa39108323bfad \
    /bin/wkhtmltopdf /bin/wkhtmltopdf

RUN echo "06139f13500db9b0b4373d40ff0faf046e536695fa836e92f41d829696d6859f  /bin/wkhtmltopdf" \
    | sha256sum -c -

ENV LANG=C.UTF-8 \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    PATH=/usr/local/bundle/bin:$PATH

ENV APP_HOME=/application
WORKDIR $APP_HOME
COPY . $APP_HOME

EXPOSE 4567

ENTRYPOINT ["sh", "-c", "./entrypoint.sh"]
