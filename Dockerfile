FROM debian:jessie
MAINTAINER Alex Mills <alex@asdfx.us>

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libpcre3 \
      librecode0 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libxml2 \
      libjpeg-dev \
      libpng-dev \
      libfreetype6-dev \
      libmcrypt-dev/oldstable \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

RUN mkdir /usr/include/freetype2/freetype \
        && ln -s /usr/include/freetype2/freetype.h /usr/include/freetype2/freetype/freetype.h

# phpize deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

# compile openssl, otherwise --with-openssl won't work
RUN OPENSSL_VERSION="1.0.2g" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION 5.3.29

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
                autoconf2.13 \
                libcurl4-openssl-dev \
                libpcre3-dev \
                libreadline6-dev \
                librecode-dev \
                libsqlite3-dev \
                libssl-dev \
                libxml2-dev \
                xz-utils \
      " \
      && set -x \
      && apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
      && gpg --verify php.tar.xz.asc \
      && mkdir -p /usr/src/php \
      && tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
      && rm php.tar.xz* \
      && cd /usr/src/php \
      && ./configure \
            --with-jpeg-dir \
            --with-png-dir \
            --with-vpx-dir \
            --with-gd \
            --enable-gd-native-ttf \
            --with-freetype-dir \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-fpm \
            --with-fpm-user=www-data \
            --with-fpm-group=www-data \
            --disable-cgi \
            --enable-mysqlnd \
            --with-mysql \
            --with-pdo-mysql \
            --with-curl \
            --with-openssl=/usr/local/ssl \
            --with-readline \
            --with-recode \
            --with-zlib \
      && make -j"$(nproc)" \
      && make install \
      && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
      && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
      && make clean

COPY scripts/docker-php-* /usr/local/bin/

COPY lib/php5.3-mcrypt/* /usr/local/lib/php/extensions/php5.3-mcrypt/

RUN cd /usr/local/lib/php/extensions/php5.3-mcrypt \
        && phpize \
        && ./configure \
        && make \
        && make install

WORKDIR /var/www/html
COPY conf/php-fpm.conf /usr/local/etc/
COPY conf/php.ini /usr/local/etc/php



EXPOSE 9000
CMD ["php-fpm"]
