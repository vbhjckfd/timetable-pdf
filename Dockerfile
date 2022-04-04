FROM ruby:3.1-alpine

RUN apk add --update --no-cache \
    libgcc libstdc++ libx11 glib libxrender libxext libintl \
    ttf-dejavu ttf-droid ttf-freefont ttf-liberation

# On alpine static compiled patched qt headless wkhtmltopdf (46.8 MB).
# Compilation took place in Travis CI with auto push to Docker Hub see
# BUILD_LOG env. Checksum is printed in line 13685.
COPY --from=madnight/alpine-wkhtmltopdf-builder:0.12.5-alpine3.10-606718795 \
    /bin/wkhtmltopdf /bin/wkhtmltopdf
ENV BUILD_LOG=https://api.travis-ci.org/v3/job/606718795/log.txt

RUN [ "$(sha256sum /bin/wkhtmltopdf | awk '{ print $1 }')" == \
      "$(wget -q -O - $BUILD_LOG | sed -n '13685p' | awk '{ print $1 }')" ]

# Change to the application's directory
ENV APP_HOME /application
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/

RUN apk add build-base && bundle install && apk del build-base linux-headers pcre-dev openssl-dev && rm -rf /var/cache/apk/*

ADD . $APP_HOME

EXPOSE 4567

ENTRYPOINT ["sh", "-c", "./entrypoint.sh"]