#!/bin/bash
# Passbolt on Railway: persistent keys on the volume, volume owned by www-data, first admin from variables.
set -eu

die() { echo "passbolt-railway: $*" >&2; exit 1; }

DATA=/data
APP_UID=33
APP_GID=33
WEBROOT_AVATAR=/usr/share/php/passbolt/webroot/img/avatar

[ -n "${PASSBOLT_SETUP_SECRET:-}" ] || die "PASSBOLT_SETUP_SECRET is empty - the first administrator could not be created"
[ "${#PASSBOLT_SETUP_SECRET}" -ge 16 ] || die "PASSBOLT_SETUP_SECRET must be at least 16 characters"
[ -n "${DATASOURCES_DEFAULT_HOST:-}" ] || die "DATASOURCES_DEFAULT_HOST is empty"
[ -n "${DATASOURCES_DEFAULT_PASSWORD:-}" ] || die "DATASOURCES_DEFAULT_PASSWORD is empty"
[ -n "${APP_FULL_BASE_URL:-}" ] || die "APP_FULL_BASE_URL is empty"

mkdir -p "$DATA/gpg" "$DATA/jwt" "$DATA/avatar"
# first boot only: keep the stock avatars next to uploaded ones
[ -d "$WEBROOT_AVATAR" ] && [ ! -L "$WEBROOT_AVATAR" ] && cp -an "$WEBROOT_AVATAR/." "$DATA/avatar/"
chown -R "$APP_UID:$APP_GID" "$DATA"
chmod 770 "$DATA/gpg"
chmod 750 "$DATA/jwt"
echo "passbolt-railway: $DATA owner=$(stat -c %u:%g "$DATA") port=${PORT:-unset}"

for d in gpg jwt; do
  rm -rf "/etc/passbolt/$d"
  ln -s "$DATA/$d" "/etc/passbolt/$d"
done
if [ ! -L "$WEBROOT_AVATAR" ]; then
  rm -rf "$WEBROOT_AVATAR"
  ln -s "$DATA/avatar" "$WEBROOT_AVATAR"
fi

# supervisord opens /dev/stdout and /dev/stderr by name for php-fpm, nginx and cron; after the drop to uid 33 that
# open is refused because the container's stdio pipes belong to root (spawnerr ... EACCES, all three programs FATAL).
# Give the app user a fifo and relay it to the real stderr from a root process.
LOGFIFO=/run/passbolt-log.fifo
rm -f "$LOGFIFO"
mkfifo "$LOGFIFO"
chown "$APP_UID:$APP_GID" "$LOGFIFO"
cat < "$LOGFIFO" >&2 &
: > /run/supervisord.pid
chown "$APP_UID:$APP_GID" /run/supervisord.pid

# the bootstrap waits for the web server, so it can run beside the stock entrypoint
setpriv --reuid="$APP_UID" --regid="$APP_GID" --init-groups /usr/local/bin/railway-bootstrap.sh > "$LOGFIFO" 2>&1 &

exec setpriv --reuid="$APP_UID" --regid="$APP_GID" --init-groups "$@" > "$LOGFIFO" 2>&1
