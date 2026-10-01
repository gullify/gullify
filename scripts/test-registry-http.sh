#!/bin/sh
# Sonde HTTP du service d'inscription : on parle à l'API comme le fera
# l'installateur, en simulant les deux relais qui posent X-Forwarded-For.
set -e
cd /app/public
php -S 127.0.0.1:8080 >/tmp/serveur.log 2>&1 &
sleep 2

ok=0; ko=0
verifie() { # $1 = quoi, $2 = attendu, $3 = obtenu
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"
  else ko=$((ko+1)); echo "  ÉCHEC $1 — attendu [$2], obtenu [$3]"; fi
}
appel() { # $1 = méthode, $2 = chemin, $3 = corps, $4 = XFF
  if [ "$1" = "GET" ]; then
    curl -s -H "X-Forwarded-For: ${4:-24.48.72.96}, 127.0.0.1" "http://127.0.0.1:8080$2"
  else
    curl -s -X POST -H "Content-Type: application/json" \
      -H "X-Forwarded-For: ${4:-24.48.72.96}, 127.0.0.1" -d "$3" "http://127.0.0.1:8080$2"
  fi
}
champ() { printf '%s' "$1" | php -r '$j=json_decode(stream_get_contents(STDIN),true); $c=explode(".",$argv[1]); foreach($c as $k){ $j = is_array($j)&&array_key_exists($k,$j) ? $j[$k] : null; } echo is_bool($j)?($j?"true":"false"):(is_null($j)?"null":$j);' "$2"; }

echo "\n— Un nom libre —"
R=$(appel GET "/api/v2/registry.php?action=disponible&nom=la-maison")
verifie "libre" "true" "$(champ "$R" data.libre)"
verifie "l'adresse est annoncée" "la-maison.gullify.app" "$(champ "$R" data.adresse)"

echo "\n— Un nom réservé —"
R=$(appel GET "/api/v2/registry.php?action=disponible&nom=www")
verifie "www n'est pas libre" "false" "$(champ "$R" data.libre)"
verifie "et on dit pourquoi" "Ce nom est réservé." "$(champ "$R" data.motif)"

echo "\n— Réserver —"
R=$(appel POST "/api/v2/registry.php?action=reserver" '{"nom":"la-maison","courriel":"moi@exemple.ca"}')
RES=$(champ "$R" data.reservation)
verifie "une réservation est rendue" "32" "$(printf '%s' "$RES" | wc -c | tr -d ' ')"

R=$(appel POST "/api/v2/registry.php?action=reserver" '{"nom":"la-maison","courriel":"autre@exemple.ca"}' "9.9.9.9")
verifie "le même nom est refusé" "Ce nom est déjà pris." "$(champ "$R" error.message)"

echo "\n— Tant que ce n'est pas confirmé —"
R=$(appel GET "/api/v2/registry.php?action=etat&reservation=$RES")
verifie "l'état reste en attente" "pending" "$(champ "$R" data.state)"
verifie "et aucun jeton n'est remis" "null" "$(champ "$R" data.token)"

echo "\n— Le clic dans le courriel —"
CODE=$(php -r '
require "/app/src/AppConfig.php";
$db = AppConfig::getDB();
echo (string)$db->query("SELECT confirm_code FROM registry_servers WHERE name=\"la-maison\"")->fetchColumn();')
PAGE=$(curl -s -H "X-Forwarded-For: 24.48.72.96, 127.0.0.1" "http://127.0.0.1:8080/confirmer-serveur.php?code=$CODE")
verifie "la page dit que c'est confirmé" "1" "$(printf '%s' "$PAGE" | grep -c "C.est confirm")"
verifie "et affiche l'adresse" "1" "$(printf '%s' "$PAGE" | grep -c "la-maison.gullify.app")"
PAGE=$(curl -s "http://127.0.0.1:8080/confirmer-serveur.php?code=deadbeef")
verifie "un code inventé est éconduit" "1" "$(printf '%s' "$PAGE" | grep -c "ne marche plus")"

echo "\n— Le jeton, puis l'IP —"
R=$(appel GET "/api/v2/registry.php?action=etat&reservation=$RES")
JETON=$(champ "$R" data.token)
verifie "le jeton est remis" "48" "$(printf '%s' "$JETON" | wc -c | tr -d ' ')"
verifie "l'état est actif" "active" "$(champ "$R" data.state)"

R=$(appel POST "/api/v2/registry.php?action=ip" "{\"jeton\":\"$JETON\"}" "24.48.72.96")
verifie "première annonce : rien ne change" "false" "$(champ "$R" data.changed)"
R=$(appel POST "/api/v2/registry.php?action=ip" "{\"jeton\":\"$JETON\"}" "66.130.1.2")
verifie "l'IP du demandeur est celle publiée" "66.130.1.2" "$(champ "$R" data.ip)"
verifie "et le DNS a bougé" "true" "$(champ "$R" data.changed)"

echo "\n— On ne publie pas l'IP d'un autre —"
R=$(appel POST "/api/v2/registry.php?action=ip" "{\"jeton\":\"$JETON\",\"ip\":\"1.1.1.1\"}" "66.130.1.2")
verifie "l'IP déclarée dans le corps est ignorée" "66.130.1.2" "$(champ "$R" data.ip)"

echo "\n— Les adresses privées ne comptent pas —"
R=$(appel POST "/api/v2/registry.php?action=ip" "{\"jeton\":\"$JETON\"}" "192.168.1.50")
verifie "une IP de réseau local est refusée" "adresse_invisible" "$(champ "$R" error.code)"
R=$(appel GET "/api/v2/registry.php?action=disponible&nom=derriere-un-vpn" "10.0.0.9")
verifie "mais chercher un nom reste possible" "true" "$(champ "$R" data.libre)"

echo "\n— Un incident —"
R=$(appel POST "/api/v2/registry.php?action=incident" '{"genre":"cgnat","detail":"100.70.0.1"}')
verifie "l'incident est noté" "true" "$(champ "$R" data.note)"

echo "\n— Une action inconnue —"
R=$(appel GET "/api/v2/registry.php?action=nimportequoi")
verifie "elle est refusée proprement" "action" "$(champ "$R" error.code)"

printf "\n%s %d vérifications passées, %d en échec\n" "$([ $ko -eq 0 ] && echo ✓ || echo ✗)" "$ok" "$ko"
[ $ko -eq 0 ]
