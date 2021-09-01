FROM php:7.4-fpm

ARG ENV

#Fix mismatch of hash
COPY docker/badproxy /etc/apt/apt.conf.d/99fixbadproxy

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python \
    patchelf

RUN cd /usr/src \
  && git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git --progress --verbose \
  && export PATH=`pwd`/depot_tools:"$PATH" \
  \
  && fetch v8 \
  && cd v8 \
  && git checkout 7.5.289 \
  && gclient sync \
  && tools/dev/v8gen.py -vv x64.release -- is_component_build=true use_custom_libcxx=false \
  && ninja -C out.gn/x64.release

RUN cd /usr/src/v8 \
  && mkdir -p /opt/v8/lib \
  && mkdir -p /opt/v8/include \
  && cp out.gn/x64.release/lib*.so out.gn/x64.release/*_blob.bin \
       out.gn/x64.release/icudtl.dat /opt/v8/lib/ \
  && cp -R include/* /opt/v8/include/ \
  && for A in /opt/v8/lib/*.so; do patchelf --set-rpath '$ORIGIN' $A; done

RUN cd /usr/src \
  && git clone https://github.com/derrekbertrand/v8js.git \
  && cd v8js \
  && phpize \
  && ./configure --with-v8js=/opt/v8 LDFLAGS="-lstdc++" \
  && export NO_INTERACTION=1 \
  && make \
# TODO fix v8js library ERROR one test
# && make test
  && make install \
  && docker-php-ext-enable v8js

RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip-dev libwebp-dev libjpeg62-turbo-dev libpng-dev libxpm-dev libfreetype6-dev zlib1g-dev \
    zip unzip procps \
    libicu-dev

RUN docker-php-ext-configure gd --with-webp --with-jpeg --with-xpm --with-freetype \
 && docker-php-ext-configure opcache --enable-opcache \
 && docker-php-ext-configure intl \
 && docker-php-ext-install gd mysqli pdo pdo_mysql sockets opcache zip intl

RUN pecl install xdebug apcu

COPY config/*.${ENV}.ini /usr/local/etc/php/conf.d
COPY config/*.common.ini /usr/local/etc/php/conf.d
COPY config/zz-docker.conf /usr/local/etc/php-fpm.d
COPY config/opcache.ini /usr/local/etc/php/conf.d
COPY config/apcu.ini /usr/local/etc/php/conf.d

WORKDIR /var/www

RUN usermod -u 1000 www-data

CMD ["php-fpm"]
