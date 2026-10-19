<?php
/**
 * Les comptes de la maison (GulliOS) — voir ~/gullios/CONTRAT-COMPTES.md.
 *
 * Quand COMPTES_URL est posé dans le .env, on se connecte à GulliFY par
 * COURRIEL + mot de passe de la maison, vérifiés par le service Comptes
 * (POST /verifier). Le compte LOCAL est retrouvé par `users.compte_id`, ou créé
 * à la première connexion (non admin, lit tout le dossier de musique) ; nom,
 * courriel et photo sont recopiés depuis Comptes. GulliFY émet ensuite SON
 * jeton, comme avant. La connexion par nom d'utilisateur est alors refusée
 * (Auth::verifyPassword) et le mot de passe local ne sert plus à rien (valeur
 * aléatoire jamais communiquée).
 *
 * Sans COMPTES_URL, rien de tout cela ne s'applique : la connexion par nom
 * d'utilisateur marche à l'identique.
 */
require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/MusicPaths.php';
require_once __DIR__ . '/Avatar.php';

/** Un refus de Comptes, traduit pour l'API de GulliFY (code, message, statut HTTP). */
class ComptesErreur extends RuntimeException
{
    public function __construct(public readonly string $code_api, string $message, public readonly int $http)
    {
        parent::__construct($message);
    }
}

class Comptes
{
    public const MESSAGE_GERE = "Les mots de passe de GulliFY sont gérés par les comptes de la maison (Ma maison).";

    /** La maison a basculé sur les comptes communs ? */
    public static function actif(): bool
    {
        return trim((string)AppConfig::get('comptes.url', '')) !== '';
    }

    /**
     * Une requête à Comptes. Rend [statut HTTP, corps décodé|null, corps brut].
     * Le jeton ne quitte jamais l'en-tête Authorization.
     */
    private static function appeler(string $methode, string $chemin, ?array $corps = null): array
    {
        $url = rtrim((string)AppConfig::get('comptes.url', ''), '/') . $chemin;
        $entetes = ['Authorization: Bearer ' . (string)AppConfig::get('comptes.jeton', ''), 'Accept: application/json'];
        $contenu = null;
        if ($corps !== null) {
            $entetes[] = 'Content-Type: application/json';
            $contenu = json_encode($corps, JSON_UNESCAPED_UNICODE);
        }
        $ctx = stream_context_create(['http' => [
            'method'        => $methode,
            'header'        => implode("\r\n", $entetes),
            'content'       => $contenu,
            'timeout'       => 10,
            'ignore_errors' => true,   // lire aussi le corps des 4xx
        ]]);
        $brut = @file_get_contents($url, false, $ctx);
        $statut = 0;
        foreach ($http_response_header ?? [] as $ligne) {
            if (preg_match('#^HTTP/\S+\s+(\d{3})#', $ligne, $m)) $statut = (int)$m[1];
        }
        if ($brut === false || $statut === 0) {
            error_log('Comptes injoignable : ' . $methode . ' ' . $chemin);
            throw new ComptesErreur('comptes_injoignable', "Le service des comptes de la maison ne répond pas. Réessaie dans un instant.", 503);
        }
        $json = json_decode($brut, true);
        return [$statut, is_array($json) ? $json : null, $brut];
    }

    /** L'adresse de celui qui se connecte, pour le verrou par IP de Comptes. */
    public static function ipClient(): string
    {
        $distante = (string)($_SERVER['REMOTE_ADDR'] ?? '');
        // Derrière le Caddy du conteneur, REMOTE_ADDR est celle du relais :
        // la première adresse de X-Forwarded-For est celle du demandeur.
        if ($distante === '' || !filter_var($distante, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
            foreach (explode(',', (string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? '')) as $morceau) {
                $ip = trim($morceau);
                if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
            }
        }
        return $distante;
    }

    /**
     * Courriel + mot de passe → la ligne `users` locale (créée au besoin).
     * Lève ComptesErreur sur tout refus.
     */
    public static function connecter(string $courriel, string $motDePasse, string $ip): array
    {
        $courriel = strtolower(trim($courriel));
        [$statut, $j] = self::appeler('POST', '/verifier', [
            'courriel' => $courriel, 'mot_de_passe' => $motDePasse, 'ip' => $ip,
        ]);
        $code = (string)($j['code'] ?? '');
        if ($statut === 401) {
            throw new ComptesErreur('invalid_credentials', 'Courriel ou mot de passe incorrect.', 401);
        }
        if ($statut === 403 && $code === 'desactive') {
            throw new ComptesErreur('account_disabled', 'Ce compte est désactivé. Demande à la personne qui gère la maison de le réactiver.', 403);
        }
        if ($statut === 403) {
            throw new ComptesErreur('sans_acces', "Ton compte n'a pas accès à GulliFY. Demande à l'administrateur de la maison.", 403);
        }
        if ($statut === 429) {
            throw new ComptesErreur('bloque', self::messageBloque($j['jusqua'] ?? null), 429);
        }
        if ($statut !== 200 || !isset($j['id'])) {
            error_log("Comptes /verifier : réponse inattendue ($statut)");
            throw new ComptesErreur('comptes_injoignable', "Le service des comptes de la maison a mal répondu. Réessaie dans un instant.", 502);
        }

        $user = self::provisionner($j);
        if (empty($user['is_active'])) {
            // Ma maison désactive aussi le compte DANS l'app (jetons coupés).
            throw new ComptesErreur('account_disabled', 'Ce compte est désactivé. Demande à la personne qui gère la maison de le réactiver.', 403);
        }
        if (!empty($j['photo'])) self::recopierPhoto((string)$j['id'], (int)$user['id']);
        return $user;
    }

    private static function messageBloque($jusqua): string
    {
        $t = is_string($jusqua) ? strtotime($jusqua) : false;
        if ($t !== false && $t > time()) {
            $min = (int)ceil(($t - time()) / 60);
            return "Trop d'essais ratés : réessaie dans $min minute" . ($min > 1 ? 's' : '') . '.';
        }
        return "Trop d'essais ratés : réessaie un peu plus tard.";
    }

    /**
     * Retrouve (par compte_id) ou crée le compte local, et y recopie nom,
     * courriel et `doit_changer`.
     */
    private static function provisionner(array $c): array
    {
        $db = AppConfig::getDB();
        $compteId = (string)$c['id'];
        $nom = trim((string)($c['nom'] ?? ''));
        $courriel = strtolower(trim((string)($c['courriel'] ?? '')));
        $doitChanger = !empty($c['doit_changer']) ? 1 : 0;

        $trouver = $db->prepare('SELECT * FROM users WHERE compte_id = ?');
        $trouver->execute([$compteId]);
        $u = $trouver->fetch(PDO::FETCH_ASSOC);

        if (!$u) {
            $identifiant = self::nomUtilisateurLibre($db, $nom !== '' ? $nom : (strstr($courriel, '@', true) ?: 'compte'));
            try {
                // Mot de passe local : aléatoire, jamais communiqué, jamais utilisé.
                $db->prepare(
                    'INSERT INTO users (username, password_hash, full_name, is_admin, music_directory, compte_id, email, must_change_password)
                     VALUES (?, ?, ?, 0, ?, ?, ?, ?)'
                )->execute([
                    $identifiant, password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT),
                    $nom !== '' ? mb_substr($nom, 0, 100) : null, GULLIFY_RACINE, $compteId,
                    $courriel !== '' ? $courriel : null, $doitChanger,
                ]);
            } catch (PDOException $e) {
                // Deux premières connexions simultanées : l'autre l'a créé.
                if ($e->getCode() !== '23000') throw $e;
            }
            $trouver->execute([$compteId]);
            $u = $trouver->fetch(PDO::FETCH_ASSOC);
            if (!$u) throw new RuntimeException('Compte local introuvable après création');
            return $u;
        }

        $db->prepare('UPDATE users SET full_name = COALESCE(?, full_name), email = ?, must_change_password = ? WHERE id = ?')
            ->execute([$nom !== '' ? mb_substr($nom, 0, 100) : null, $courriel !== '' ? $courriel : $u['email'], $doitChanger, (int)$u['id']]);
        $trouver->execute([$compteId]);
        return $trouver->fetch(PDO::FETCH_ASSOC);
    }

    /** La photo de Comptes devient l'avatar de GulliFY (best effort). */
    private static function recopierPhoto(string $compteId, int $userId): void
    {
        try {
            [$statut, , $brut] = self::appeler('GET', '/personnes/' . rawurlencode($compteId) . '/photo');
            if ($statut !== 200 || $brut === '' || strlen($brut) > 5 * 1024 * 1024) return;
            $info = @getimagesizefromstring($brut);
            $mime = is_array($info) ? ($info['mime'] ?? '') : '';
            if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) return;
            $tmp = tempnam(sys_get_temp_dir(), 'photo');
            try {
                file_put_contents($tmp, $brut);
                Avatar::store($userId, $tmp, $mime);
            } finally {
                @unlink($tmp);
            }
        } catch (Throwable $e) {
            error_log('Comptes : photo non recopiée (' . $e->getMessage() . ')');
        }
    }

    /**
     * Changement de mot de passe par la personne elle-même (POST /changer),
     * puis `doit_changer` levé localement et les autres sessions fermées.
     */
    public static function changer(array $user, string $ancien, string $nouveau, ?string $sessionGardee): void
    {
        $compteId = (string)($user['compte_id'] ?? '');
        if ($compteId === '') {
            throw new ComptesErreur('sans_compte', "Ce compte n'est pas encore relié aux comptes de la maison. Demande à la personne qui gère la maison.", 400);
        }
        [$statut] = self::appeler('POST', '/changer', ['id' => $compteId, 'ancien' => $ancien, 'nouveau' => $nouveau]);
        if ($statut === 401) throw new ComptesErreur('wrong_password', 'Le mot de passe actuel est incorrect.', 400);
        if ($statut === 422) throw new ComptesErreur('weak_password', "Le nouveau mot de passe doit faire au moins 10 caractères et être différent de l'ancien.", 400);
        if ($statut !== 200) {
            error_log("Comptes /changer : réponse inattendue ($statut)");
            throw new ComptesErreur('comptes_injoignable', "Le service des comptes de la maison a mal répondu. Réessaie dans un instant.", 502);
        }
        $db = AppConfig::getDB();
        $db->prepare('UPDATE users SET must_change_password = 0 WHERE id = ?')->execute([(int)$user['id']]);
        // Le mot de passe d'application Subsonic, indépendant, reste valable.
        $db->prepare('DELETE FROM sessions WHERE user_id = ? AND id <> ?')
            ->execute([(int)$user['id'], (string)$sessionGardee]);
    }

    /** Un nom d'utilisateur valide (lettres, chiffres, _ - .) et libre, tiré du nom. */
    public static function nomUtilisateurLibre(PDO $db, string $nom): string
    {
        $base = $nom;
        if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $base)) {
            $t = @iconv('UTF-8', 'ASCII//TRANSLIT', $nom);
            $base = strtolower($t !== false ? $t : $nom);
            $base = preg_replace('/[^a-z0-9_\-\.]+/', '.', $base);
            $base = trim(preg_replace('/\.{2,}/', '.', $base), '.-_');
        }
        $base = substr($base, 0, 45);
        if ($base === '') $base = 'compte';

        $st = $db->prepare('SELECT 1 FROM users WHERE username = ?');
        $candidat = $base;
        for ($n = 2; ; $n++) {
            $st->execute([$candidat]);
            if ($st->fetchColumn() === false) return $candidat;
            $candidat = $base . $n;
        }
    }

    /** Mot de passe d'application Subsonic : 20 caractères lisibles (ni 0/O, ni 1/l/I). */
    public static function nouveauMotDePasseSubsonic(): string
    {
        $alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $s = '';
        for ($i = 0; $i < 20; $i++) $s .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        return $s;
    }
}
