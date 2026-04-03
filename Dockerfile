# ── Odoo 19.0 Community – from source ──
FROM python:3.12-bookworm

LABEL maintainer="Odoo 19 Docker <christophe@example.com>"

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# ── System dependencies ──
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        fonts-noto-cjk \
        gnupg \
        libffi-dev \
        libgeoip-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        node-less \
        npm \
        postgresql-client \
        python3-dev \
        python3-magic \
        python3-renderpm \
        wkhtmltopdf \
        xz-utils \
        zlib1g-dev \
    && npm install -g rtlcss \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Create odoo user ──
RUN useradd --create-home --shell /bin/bash odoo

# ── Copy source & install Python deps ──
WORKDIR /opt/odoo

COPY requirements.txt /opt/odoo/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . /opt/odoo

# ── Config & data directories ──
RUN mkdir -p /etc/odoo /var/lib/odoo \
    && chown -R odoo:odoo /etc/odoo /var/lib/odoo /opt/odoo

COPY docker/odoo.conf /etc/odoo/odoo.conf

# ── Volumes ──
VOLUME ["/var/lib/odoo", "/opt/odoo/addons"]

# ── Expose Odoo ports ──
EXPOSE 8069 8071 8072

# ── Entrypoint ──
USER odoo

ENTRYPOINT ["python3", "/opt/odoo/odoo-bin"]
CMD ["-c", "/etc/odoo/odoo.conf"]
