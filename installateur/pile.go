package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Poser la pile : écrire les fichiers, tirer les images, démarrer, puis faire
// soi-même la configuration que l'assistant du serveur demanderait.
//
// L'idée directrice : quelqu'un qui installe GulliFY ne doit jamais voir un
// fichier de configuration, ni un assistant en plusieurs étapes. Il a déjà
// répondu aux trois questions qui comptent (son nom, sa musique, son compte) ;
// tout le reste se déduit.

// L'image publiée. Le dépôt sert à la construire ; les gens, eux, la tirent.
const imageParDefaut = "ghcr.io/gullify/gullify:latest"

// Le nom du projet Docker, imposé plutôt que déduit.
//
// Sans ce nom, Docker le tire du DOSSIER : une pile posée dans « Gullify »
// s'appelle « gullify », partage ses volumes avec toute autre pile du même nom
// sur la machine, et un `down` sur l'une emporte l'autre. C'est exactement
// comme ça qu'une base de production a été effacée pendant la mise au point de
// cet installateur. Un nom explicite, distinct, et le problème ne peut plus se
// poser — y compris chez quelqu'un qui aurait déjà un projet « gullify ».
const projetCompose = "gullify-serveur"

// Les ports que la pile occupe sur la machine.
//
// 80 et 443 par défaut, parce que c'est ce qu'attend un certificat Let's
// Encrypt et ce qui rend le serveur joignable sans rien préciser. On peut les
// changer : un routeur sait rediriger le 80 du dehors vers un autre port du
// dedans, et certaines machines ont déjà un serveur web installé.
func portHTTP() string {
	if p := os.Getenv("GULLIFY_PORT_HTTP"); p != "" {
		return p
	}
	return "80"
}

func portHTTPS() string {
	if p := os.Getenv("GULLIFY_PORT_HTTPS"); p != "" {
		return p
	}
	return "443"
}

func (e *Etat) lancerInstallation(w http.ResponseWriter, _ *http.Request) {
	e.repond(w, map[string]bool{"lance": true})
	go e.installe()
}

func (e *Etat) installe() {
	e.mu.Lock()
	dossier := e.DossierServeur
	musique := e.DossierMusique
	adresse := e.Adresse
	utilisateur := e.Utilisateur
	motDePasse := e.motDePasse
	e.mu.Unlock()

	etapes := []struct {
		quoi string
		fait func() error
	}{
		{fmt.Sprintf("Vérification des ports %s et %s", portHTTP(), portHTTPS()), func() error { return e.verifiePorts() }},
		{"Écriture des fichiers", func() error { return e.ecritFichiers(dossier, musique, adresse) }},
		{"Téléchargement de GulliFY", func() error { return e.tireLesImages(dossier) }},
		{"Démarrage", func() error {
			return e.docker(dossier, 5*time.Minute, "compose", "-p", projetCompose, "up", "-d")
		}},
		{"Attente du serveur", func() error { return e.attendLeServeur(3 * time.Minute) }},
		{"Préparation de la base", func() error { return e.setup("create_tables", nil) }},
		{"Création de ton compte", func() error {
			return e.setup("create_admin", map[string]string{
				"username":        utilisateur,
				"password":        motDePasse,
				"music_directory": "/music",
			})
		}},
		{"Enregistrement de ta musique", func() error {
			return e.setup("save_storage", map[string]string{
				"storage_type":    "local",
				"music_directory": "/music",
			})
		}},
		{"Dernier réglage", func() error { return e.setup("finish_setup", nil) }},
		{"Publication de ton adresse", func() error { return e.annonceIP() }},
	}

	for i, etape := range etapes {
		e.dit("%s…", etape.quoi)
		if err := etape.fait(); err != nil {
			e.echoue("%s : %v", etape.quoi, err)
			e.signale("installation", fmt.Sprintf("%s : %v", etape.quoi, err))
			return
		}
		e.mu.Lock()
		e.Progression = (i + 1) * 100 / len(etapes)
		e.mu.Unlock()
	}

	e.dit("C'est prêt.")
	e.avance("fini")
}

// tireLesImages télécharge ce qu'il faut, et sait se passer du réseau.
//
// Un échec de téléchargement n'est pas fatal si l'image est DÉJÀ sur la
// machine : c'est le cas d'une réinstallation, d'une reprise après un ennui
// de connexion, ou d'un essai contre une image construite sur place. Dans ce
// cas on continue avec ce qu'on a, en le disant.
func (e *Etat) tireLesImages(dossier string) error {
	err := e.docker(dossier, 10*time.Minute, "compose", "-p", projetCompose, "pull")
	if err == nil {
		return nil
	}

	image := imageGullify()
	if exec.Command("docker", "image", "inspect", image).Run() != nil {
		return err
	}

	e.dit("  Téléchargement impossible, mais %s est déjà sur cette machine : je continue.", image)
	return nil
}

// ── Les ports ────────────────────────────────────────────────────────────────

// verifiePorts regarde si 80 et 443 sont libres.
//
// C'est la panne la plus bête et la plus fréquente : un autre serveur web, ou
// une pile Gullify déjà lancée. Mieux vaut le dire avant de télécharger un
// gigaoctet d'images.
func (e *Etat) verifiePorts() error {
	var occupes []string
	for _, port := range []string{portHTTP(), portHTTPS()} {
		ecoute, err := net.Listen("tcp", ":"+port)
		if err != nil {
			occupes = append(occupes, port)
			continue
		}
		_ = ecoute.Close()
	}
	if len(occupes) == 0 {
		return nil
	}
	return fmt.Errorf(
		"le port %s est déjà pris par un autre programme. GulliFY en a besoin pour que ton serveur soit joignable depuis l'extérieur. Arrête l'autre programme, puis reprends",
		strings.Join(occupes, " et "),
	)
}

// ── Les fichiers ─────────────────────────────────────────────────────────────

func (e *Etat) ecritFichiers(dossier, musique, adresse string) error {
	if err := os.MkdirAll(dossier, 0o755); err != nil {
		return fmt.Errorf("impossible de créer %s : %w", dossier, err)
	}

	// Les secrets d'une installation PRÉCÉDENTE priment sur des neufs.
	//
	// MySQL ne lit son mot de passe qu'à la toute première mise en route :
	// ensuite il garde celui-là, gravé dans son volume. Réinstaller en
	// fabriquant de nouveaux secrets donnerait une pile qui ne peut plus ouvrir
	// sa propre base — « Access denied », sans que rien n'explique pourquoi.
	ancien := litEnv(filepath.Join(dossier, ".env"))
	motDePasseBase := reprendre(ancien, "MYSQL_PASSWORD", 18)
	motDePasseRacine := reprendre(ancien, "MYSQL_ROOT_PASSWORD", 18)
	secretApp := reprendre(ancien, "APP_SECRET", 32)

	env := fmt.Sprintf(`# Écrit par l'installateur GulliFY — modifiable, mais prudence.
GULLIFY_SETUP_DONE=false

MYSQL_HOST=db
MYSQL_PORT=3306
MYSQL_DATABASE=gullify
MYSQL_USER=gullify
MYSQL_PASSWORD=%s
MYSQL_ROOT_PASSWORD=%s

MUSIC_HOST_PATH=%s
MUSIC_BASE_PATH=/music
DATA_PATH=/app/data

APP_DOMAIN=%s
APP_URL=https://%s
APP_DEBUG=false
APP_SECRET=%s

PUID=%d
PGID=%d
`, motDePasseBase, motDePasseRacine, musique, adresse, adresse, secretApp, utilisateurSysteme(), groupeSysteme())

	if err := os.WriteFile(filepath.Join(dossier, ".env"), []byte(env), 0o600); err != nil {
		return fmt.Errorf("impossible d'écrire la configuration : %w", err)
	}

	// Caddy obtient tout seul le certificat de ton adresse, pourvu que le port
	// 80 lui parvienne depuis l'extérieur. Le bloc « :80 » sert aux appels
	// locaux (l'installateur, et toi depuis la maison).
	caddy := `{$APP_DOMAIN:localhost} {
	reverse_proxy app:80
}

:80 {
	reverse_proxy app:80
}
`
	if err := os.WriteFile(filepath.Join(dossier, "Caddyfile"), []byte(caddy), 0o644); err != nil {
		return fmt.Errorf("impossible d'écrire la configuration du certificat : %w", err)
	}

	compose := fmt.Sprintf(`# Écrit par l'installateur GulliFY.
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "%s:80"
      - "%s:443"
      - "%s:443/udp"
    environment:
      - APP_DOMAIN=${APP_DOMAIN:-localhost}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - app
    restart: unless-stopped

  app:
    image: %s
    user: root
    expose:
      - "80"
    volumes:
      - ./.env:/app/.env
      - ${MUSIC_HOST_PATH:-./music}:/music
      - gullify_data:/app/data
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - MYSQL_HOST=db
      - MYSQL_DATABASE=gullify
      - MYSQL_USER=gullify
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: mysql:8.0
    environment:
      - MYSQL_DATABASE=gullify
      - MYSQL_USER=gullify
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
    volumes:
      - gullify_db:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 3s
      retries: 20
    restart: unless-stopped

volumes:
  gullify_data:
  gullify_db:
  caddy_data:
  caddy_config:
`, portHTTP(), portHTTPS(), portHTTPS(), imageGullify())

	if err := os.WriteFile(filepath.Join(dossier, "docker-compose.yml"), []byte(compose), 0o644); err != nil {
		return fmt.Errorf("impossible d'écrire la description de la pile : %w", err)
	}

	e.dit("Fichiers posés dans %s", dossier)
	return nil
}

// imageGullify : modifiable par variable d'environnement, pour pouvoir essayer
// l'installateur contre une image locale avant qu'elle soit publiée.
func imageGullify() string {
	if image := os.Getenv("GULLIFY_IMAGE"); image != "" {
		return image
	}
	return imageParDefaut
}

// litEnv relit un .env déjà posé. Un fichier absent n'est pas une erreur :
// c'est simplement une première installation.
func litEnv(chemin string) map[string]string {
	valeurs := map[string]string{}
	contenu, err := os.ReadFile(chemin)
	if err != nil {
		return valeurs
	}
	for _, ligne := range strings.Split(string(contenu), "\n") {
		ligne = strings.TrimSpace(ligne)
		if ligne == "" || strings.HasPrefix(ligne, "#") {
			continue
		}
		if cle, valeur, trouve := strings.Cut(ligne, "="); trouve {
			valeurs[strings.TrimSpace(cle)] = strings.TrimSpace(valeur)
		}
	}
	return valeurs
}

// reprendre rend l'ancienne valeur si elle existe, sinon un secret tout neuf.
func reprendre(ancien map[string]string, cle string, octets int) string {
	if valeur, existe := ancien[cle]; existe && valeur != "" {
		return valeur
	}
	return secret(octets)
}

func secret(octets int) string {
	b := make([]byte, octets)
	if _, err := rand.Read(b); err != nil {
		// Un mot de passe prévisible serait pire qu'un échec bruyant.
		panic("pas de source d'aléa pour fabriquer un mot de passe")
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// Sur Linux et macOS, le serveur doit écrire dans le dossier de musique avec
// les droits de la personne. Sur Windows, ces notions n'existent pas côté
// Docker : les valeurs n'y servent à rien, mais ne gênent pas.
func utilisateurSysteme() int {
	if runtime.GOOS == "windows" {
		return 1000
	}
	return os.Getuid()
}

func groupeSysteme() int {
	if runtime.GOOS == "windows" {
		return 1000
	}
	return os.Getgid()
}

// ── Docker ───────────────────────────────────────────────────────────────────

func (e *Etat) docker(dossier string, patience time.Duration, args ...string) error {
	ctx, annule := context.WithTimeout(context.Background(), patience)
	defer annule()

	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Dir = dossier

	sortie, err := cmd.CombinedOutput()
	for _, ligne := range dernieresLignes(string(sortie), 6) {
		e.dit("  %s", ligne)
	}
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("c'est trop long — connexion lente ou Docker bloqué")
	}
	if err != nil {
		return fmt.Errorf("docker %s a échoué", strings.Join(args, " "))
	}
	return nil
}

// attendLeServeur attend que la pile réponde, par le port 80 local.
func (e *Etat) attendLeServeur(patience time.Duration) error {
	client := &http.Client{Timeout: 5 * time.Second}
	limite := time.Now().Add(patience)

	for time.Now().Before(limite) {
		reponse, err := client.Get("http://127.0.0.1:" + portHTTP() + "/api/v2/ping.php")
		if err == nil {
			reponse.Body.Close()
			if reponse.StatusCode == http.StatusOK {
				return nil
			}
		}
		time.Sleep(3 * time.Second)
	}
	return fmt.Errorf("le serveur n'a pas démarré à temps — regarde le journal de Docker")
}

// setup joue une étape de l'assistant du serveur, à la place de l'utilisateur.
func (e *Etat) setup(action string, champs map[string]string) error {
	valeurs := url.Values{}
	for cle, valeur := range champs {
		valeurs.Set(cle, valeur)
	}

	client := &http.Client{Timeout: 60 * time.Second}
	reponse, err := client.PostForm("http://127.0.0.1:"+portHTTP()+"/setup/api.php?action="+action, valeurs)
	if err != nil {
		return fmt.Errorf("le serveur n'a pas répondu : %w", err)
	}
	defer reponse.Body.Close()

	var corps struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
	if err := decodeJSON(reponse, &corps); err != nil {
		return err
	}
	if !corps.Success {
		return fmt.Errorf("%s", corps.Message)
	}
	return nil
}

// decodeJSON lit une réponse JSON en disant clairement ce qui cloche quand le
// serveur renvoie autre chose — une page d'erreur PHP, par exemple.
func decodeJSON(reponse *http.Response, cible any) error {
	corps, err := io.ReadAll(io.LimitReader(reponse.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("lecture de la réponse impossible : %w", err)
	}
	if err := json.Unmarshal(corps, cible); err != nil {
		apercu := strings.TrimSpace(string(corps))
		if len(apercu) > 200 {
			apercu = apercu[:200] + "…"
		}
		return fmt.Errorf("le serveur a répondu autre chose que du JSON : %s", apercu)
	}
	return nil
}
