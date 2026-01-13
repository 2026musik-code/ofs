FROM alpine:latest

# Install Xray, Nginx, curl, gettext (for envsubst), util-linux (for uuidgen), and apache2-utils (for htpasswd)
RUN apk add --no-cache nginx curl gettext util-linux apache2-utils ca-certificates unzip \
    && mkdir -p /var/log/xray /usr/share/xray /etc/xray \
    && curl -L -H "Cache-Control: no-cache" -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip \
    && unzip /tmp/xray.zip -d /usr/share/xray \
    && mv /usr/share/xray/xray /usr/bin/xray \
    && chmod +x /usr/bin/xray \
    && rm -rf /tmp/xray.zip

# Copy Configs
COPY xray/config.json.template /etc/xray/config.json.template
COPY nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY web/index.html.template /www/index.html.template
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose Koyeb Port
ENV PORT=8000
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
