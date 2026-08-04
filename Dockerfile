# Pinned to alpine 3.18: the wkhtmltopdf binary below was built in 2019 against
# OpenSSL 1.1 and dies with "Error relocating /bin/wkhtmltopdf: SSL_CTX_free:
# symbol not found" on any newer alpine. 3.18 is the last one packaging
# openssl1.1-compat.
FROM ruby:3.1-alpine3.18

RUN apk add --update --no-cache \
    libgcc libstdc++ libx11 glib libxrender libxext libintl \
    openssl1.1-compat \
    ttf-dejavu ttf-droid ttf-freefont ttf-liberation

# On alpine static compiled patched qt headless wkhtmltopdf (46.8 MB).
# Compilation took place in Travis CI (job 606718795) with auto push to Docker
# Hub. The checksum used to be read back from that job's log at build time;
# api.travis-ci.org no longer exists, so the tag is pinned to its digest and
# the expected checksum is recorded here instead.
COPY --from=madnight/alpine-wkhtmltopdf-builder:0.12.5-alpine3.10-606718795@sha256:009bc5a3e8823b92568473f075e157b59488d0ddf3209865a7aa39108323bfad \
    /bin/wkhtmltopdf /bin/wkhtmltopdf

RUN echo "06139f13500db9b0b4373d40ff0faf046e536695fa836e92f41d829696d6859f  /bin/wkhtmltopdf" \
    | sha256sum -c -

# Change to the application's directory
ENV APP_HOME /application
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/

RUN apk add build-base && bundle install && apk del build-base linux-headers pcre-dev openssl-dev && rm -rf /var/cache/apk/*

ADD . $APP_HOME

EXPOSE 4567

ENTRYPOINT ["sh", "-c", "./entrypoint.sh"]