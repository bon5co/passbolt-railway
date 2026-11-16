#!/bin/bash
# Creates the first administrator once, with a setup link anyone holding PASSBOLT_SETUP_SECRET can compute:
#   https://<domain>/setup/start/<user id>/<token>
# where both ids are v4-shaped UUIDs taken from sha256("<secret>:uid") and sha256("<secret>:token").
# Safe to run on every boot; it only acts while no user exists, or while the administrator has not finished setup.
set -u

log() { echo "passbolt-railway: $*"; }
CAKE=/usr/share/php/passbolt/bin/cake

uuid_from() {
  local h
  h=$(printf '%s' "$PASSBOLT_SETUP_SECRET:$1" | sha256sum | cut -c1-32)
  printf '%s-%s-4%s-a%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" "${h:17:3}" "${h:20:12}"
}
UID_WANT=$(uuid_from uid)
TOKEN_WANT=$(uuid_from token)

n=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/healthcheck/status.json)" = 200 ]; do
  n=$((n + 1))
  if [ "$n" -gt 180 ]; then log "web server never answered, no administrator created"; exit 1; fi
  sleep 2
done

sql() { # sql <query> [args...] -> prints first column of first row, empty when none
  UID_WANT="$UID_WANT" TOKEN_WANT="$TOKEN_WANT" php -r '
    $pdo = new PDO("mysql:host=".getenv("DATASOURCES_DEFAULT_HOST").";port=".getenv("DATASOURCES_DEFAULT_PORT").";dbname=".getenv("DATASOURCES_DEFAULT_DATABASE"),
      getenv("DATASOURCES_DEFAULT_USERNAME"), getenv("DATASOURCES_DEFAULT_PASSWORD"), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $q = $pdo->prepare($argv[1]); $q->execute(array_slice($argv, 2));
    if ($q->columnCount() > 0) { $c = $q->fetchColumn(); if ($c !== false) echo $c; }
  ' "$@"
}

USERS=$(sql 'SELECT COUNT(*) FROM users')
if [ "$USERS" = 0 ]; then
  "$CAKE" passbolt register_user -u "$ADMIN_EMAIL" -f "$ADMIN_FIRST_NAME" -l "$ADMIN_LAST_NAME" -r admin >/dev/null 2>&1 || { log "register_user failed"; exit 1; }
  OLD=$(sql 'SELECT id FROM users WHERE username = ?' "$ADMIN_EMAIL")
  [ -n "$OLD" ] || { log "administrator row not found after register_user"; exit 1; }
  UID_WANT="$UID_WANT" TOKEN_WANT="$TOKEN_WANT" OLD="$OLD" php -r '
    $pdo = new PDO("mysql:host=".getenv("DATASOURCES_DEFAULT_HOST").";port=".getenv("DATASOURCES_DEFAULT_PORT").";dbname=".getenv("DATASOURCES_DEFAULT_DATABASE"),
      getenv("DATASOURCES_DEFAULT_USERNAME"), getenv("DATASOURCES_DEFAULT_PASSWORD"), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $pdo->exec("SET FOREIGN_KEY_CHECKS=0"); $pdo->beginTransaction();
    foreach (["users" => "id", "profiles" => "user_id", "authentication_tokens" => "user_id"] as $t => $c)
      $pdo->prepare("UPDATE $t SET $c = ? WHERE $c = ?")->execute([getenv("UID_WANT"), getenv("OLD")]);
    $pdo->prepare("UPDATE authentication_tokens SET token = ? WHERE user_id = ? AND type = \"register\"")->execute([getenv("TOKEN_WANT"), getenv("UID_WANT")]);
    $pdo->commit();
  ' || { log "could not set the setup link"; exit 1; }
  log "administrator $ADMIN_EMAIL created, setup link path /setup/start/$UID_WANT/$TOKEN_WANT"
else
  ACTIVE=$(sql 'SELECT active FROM users WHERE id = ?' "$UID_WANT")
  if [ "$ACTIVE" = 0 ]; then
    # setup not finished: renew the link's clock so a redeploy after the token's lifetime still works
    sql 'UPDATE authentication_tokens SET active = 1, created = NOW(), modified = NOW() WHERE user_id = ? AND type = "register"' "$UID_WANT" >/dev/null
    log "administrator setup pending, link renewed: /setup/start/$UID_WANT/$TOKEN_WANT"
  else
    log "administrator exists, nothing to do"
  fi
fi
