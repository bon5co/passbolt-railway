# Passbolt CE for Railway.
#
# Passbolt (passbolt/passbolt_api, AGPL-3.0) is an open source team password manager. The upstream non-root image is
# unchanged. This wrapper adds what a Railway deploy needs:
#
# 1. Railway mounts the volume root-owned and the image runs as www-data (33), so the boot script chowns /data, keeps
#    the server GPG key, the JWT keypair and avatars on it (symlinked into place) and then drops privileges with setpriv.
# 2. The database login, database name and port are baked in, so the deploy form carries no literal variables.
# 3. The first administrator is created from variables at first boot: a setup link whose user id and token are derived
#    from PASSBOLT_SETUP_SECRET, so a deployer (or an agent) can build it without reading logs or mail.
#
# upstream: passbolt/passbolt_api
FROM passbolt/passbolt:5.18.0-1-ce-non-root@sha256:cb1cde86a9eb3d2406dea42a49b174625314728632d9ddc9b8572036da130faf

USER root

ENV DATASOURCES_DEFAULT_USERNAME=passbolt \
    DATASOURCES_DEFAULT_DATABASE=passbolt \
    DATASOURCES_DEFAULT_PORT=3306 \
    PASSBOLT_PLUGINS_EXPORT_ENABLED=true \
    ADMIN_EMAIL=admin@example.com \
    ADMIN_FIRST_NAME=Admin \
    ADMIN_LAST_NAME=User

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY railway-bootstrap.sh /usr/local/bin/railway-bootstrap.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh /usr/local/bin/railway-bootstrap.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/docker-entrypoint.sh"]

EXPOSE 8080
