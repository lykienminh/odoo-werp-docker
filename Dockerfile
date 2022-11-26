FROM ubuntu:20.04
# FROM debian:bullseye-slim

# Define build constants
ENV GIT_BRANCH=15.0 \
  PYTHON_BIN=python3 \
  SERVICE_BIN=odoo-bin

# Set timezone to UTC
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
# ENV LANG C.UTF-8
# Install rtlcss (on Debian buster)
# RUN npm install -g rtlcss

# Generate locales
RUN apt update \
  && apt -yq install locales \
  && locale-gen en_US.UTF-8 \
  && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-num2words \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        libpq-dev \
        python3-dev \
        xz-utils \
        # python-pypdf2 \
        python3-pypdf2

# Install APT dependencies
ADD sources/apt.txt /opt/sources/apt.txt
RUN apt update \
  && awk '! /^ *(#|$)/' /opt/sources/apt.txt | xargs -r apt install -yq

# Create the odoo user
RUN useradd --create-home --home-dir /opt/odoo --no-log-init odoo

# Switch to user odoo to create the folders mapped with volumes, else the
# corresponding folders will be created by root on the host
USER odoo

# If the folders are created with "RUN mkdir" command, they will belong to root
# instead of odoo! Hence the "RUN /bin/bash -c" trick.
RUN /bin/bash -c "mkdir -p /opt/odoo/{etc,sources/odoo,additional_addons,data,ssh}"

# Add Odoo sources and remove .git folder in order to reduce image size
WORKDIR /opt/odoo/sources
RUN git clone --depth=1 https://github.com/odoo/odoo.git -b $GIT_BRANCH \
  && rm -rf odoo/.git
# COPY /odoo /opt/odoo/sources/odoo

ADD sources/odoo.conf /opt/odoo/etc/odoo.conf
ADD auto_addons /opt/odoo/auto_addons

USER 0

RUN apt-get update -y
RUN apt-get install -y gcc build-essential

# Install Odoo python dependencies
RUN pip3 install setuptools wheel
# RUN env LDFLAGS='-L/usr/local/lib -L/usr/local/opt/openssl/lib -L/usr/local/opt/readline/lib' pip3 install -r /opt/odoo/sources/odoo/requirements.txt -e ./odoo
# RUN pip3 install -r /opt/odoo/sources/odoo/requirements.txt -e ./odoo

# Install extra python dependencies
ADD sources/pip.txt /opt/sources/pip.txt
RUN pip3 install -r /opt/sources/pip.txt
ADD sources/requirements.txt /opt/sources/requirements.txt
# RUN env LDFLAGS='-L/usr/local/lib -L/usr/local/opt/openssl/lib -L/usr/local/opt/readline/lib' \
RUN pip3 install -r /opt/sources/requirements.txt -e /opt/odoo/sources/odoo

# Install wkhtmltopdf based on QT5
# ADD https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.focal_amd64.deb \
#   /opt/sources/wkhtmltox.deb
# RUN apt update \
#   && apt install -yq xfonts-base xfonts-75dpi \
#   && dpkg -i /opt/sources/wkhtmltox.deb

# Install postgresql-client
RUN apt update && apt install -yq lsb-release
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt update && apt install -yq postgresql-client

# Startup script for custom setup
ADD sources/startup.sh /opt/scripts/startup.sh

# Provide read/write access to odoo group (for host user mapping). This command
# must run before creating the volumes since they become readonly until the
# container is started.
RUN chmod -R 775 /opt/odoo && chown -R odoo:odoo /opt/odoo

VOLUME [ \
  "/opt/odoo/etc", \
  "/opt/odoo/additional_addons", \
  "/opt/odoo/data", \
  "/opt/odoo/ssh", \
  "/opt/scripts" \
]

# Use README for the help & man commands
ADD README.md /usr/share/man/man.txt
# Remove anchors and links to anchors to improve readability
RUN sed -i '/^<a name=/ d' /usr/share/man/man.txt
RUN sed -i -e 's/\[\^\]\[toc\]//g' /usr/share/man/man.txt
RUN sed -i -e 's/\(\[.*\]\)(#.*)/\1/g' /usr/share/man/man.txt
# For help command, only keep the "Usage" section
RUN from=$( awk '/^## Usage/{ print NR; exit }' /usr/share/man/man.txt ) && \
  from=$(expr $from + 1) && \
  to=$( awk '/^    \$ docker-compose up/{ print NR; exit }' /usr/share/man/man.txt ) && \
  head -n $to /usr/share/man/man.txt | \
  tail -n +$from | \
  tee /usr/share/man/help.txt > /dev/null

# Use dumb-init as init system to launch the boot script
ADD https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_arm64.deb /opt/sources/dumb-init.deb
RUN dpkg -i /opt/sources/dumb-init.deb
ADD bin/boot /usr/bin/boot
ENTRYPOINT [ "/usr/bin/dumb-init", "/usr/bin/boot" ]
CMD [ "help" ]

# ADD https://files.pythonhosted.org/packages/6d/b5/495011623878f1000a2bfa62fa54c3b491071f0c77062dcd1bd86e2b9764/reportlab-3.5.13.tar.gz /opt/odoo/sources/reportlab.tar.gz
# RUN tar -xzf reportlab.tar.gz -C ./odoo && rm reportlab.tar.gz
RUN pip3 install --upgrade pip && pip3 install Jinja2 MarkupSafe

# Expose the odoo ports (for linked containers)
EXPOSE 8069 8072
