package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// Etat est tout ce que l'installation sait d'elle-même.
//
// Une seule structure, protégée par un verrou, que la page interroge en boucle.
// C'est volontairement bête : une installation est linéaire, dure quelques
// minutes, et doit pouvoir être reprise du regard à tout moment — « où en
// est-on, et qu'est-ce qui bloque ».
type Etat struct {
	mu sync.Mutex

	Etape   string   `json:"etape"`   // bienvenue, docker, nom, confirmation, reglages, installation, fini
	Erreur  string   `json:"erreur"`  // vide si tout va bien
	Journal []string `json:"journal"` // ce qui s'est passé, en français, pour l'écran

	Docker    DockerEtat `json:"docker"`
	Prerequis Prerequis  `json:"prerequis"`
	Reseau    Diagnostic `json:"reseau"`

	Nom         string `json:"nom"`
	Courriel    string `json:"courriel"`
	Adresse     string `json:"adresse"` // nom.gullify.app
	Reservation string `json:"-"`       // ne sort jamais : c'est un secret
	Jeton       string `json:"-"`       // idem

	DossierMusique string `json:"dossierMusique"`
	DossierServeur string `json:"dossierServeur"`
	Utilisateur    string `json:"utilisateur"`
	motDePasse     string // jamais sérialisé

	Progression int `json:"progression"` // 0 à 100, pendant l'installation

	service string
	fini    chan struct{}
	ferme   sync.Once
}

func NouvelEtat(service string) *Etat {
	return &Etat{
		Etape:          "bienvenue",
		service:        strings.TrimRight(service, "/"),
		DossierServeur: dossierParDefaut(),
		fini:           make(chan struct{}),
	}
}

func (e *Etat) Fini() <-chan struct{} { return e.fini }

// dit ajoute une ligne au journal visible à l'écran.
func (e *Etat) dit(format string, args ...any) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.Journal = append(e.Journal, fmt.Sprintf(format, args...))
}

func (e *Etat) echoue(format string, args ...any) {
	message := fmt.Sprintf(format, args...)
	e.mu.Lock()
	e.Erreur = message
	e.Journal = append(e.Journal, "⚠ "+message)
	e.mu.Unlock()
}

func (e *Etat) avance(etape string) {
	e.mu.Lock()
	e.Etape = etape
	e.Erreur = ""
	e.mu.Unlock()
}

// dossierParDefaut : là où la pile sera posée, au chaud dans le dossier de
// l'utilisateur — pas besoin des droits d'administrateur.
func dossierParDefaut() string {
	maison, err := os.UserHomeDir()
	if err != nil {
		return "gullify"
	}
	return filepath.Join(maison, "Gullify")
}

// ── L'API locale ─────────────────────────────────────────────────────────────

// Router branche les points d'entrée, tous protégés par le jeton de session.
func (e *Etat) Router(mux *http.ServeMux, jeton string) {
	garde := func(h http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			// Le jeton arrive en en-tête (appels de la page) ou en paramètre
			// (première ouverture). Comparaison simple : il est aléatoire et
			// ne vit que le temps de l'installation.
			fourni := r.Header.Get("X-Cle")
			if fourni == "" {
				fourni = r.URL.Query().Get("cle")
			}
			if fourni != jeton {
				http.Error(w, "clé absente ou incorrecte", http.StatusForbidden)
				return
			}
			h(w, r)
		}
	}

	mux.HandleFunc("/api/etat", garde(e.lireEtat))
	mux.HandleFunc("/api/dossiers", garde(e.listerDossiers))
	mux.HandleFunc("/api/docker", garde(e.verifierDocker))
	mux.HandleFunc("/api/docker/installer", garde(e.installerDocker))
	mux.HandleFunc("/api/prerequis/reparer", garde(e.reparerPrerequis))
	mux.HandleFunc("/api/reseau", garde(e.verifierReseau))
	mux.HandleFunc("/api/reseau/ouvrir", garde(e.ouvrirLesPorts))
	mux.HandleFunc("/api/joignable", garde(e.verifierJoignable))
	mux.HandleFunc("/api/nom/verifier", garde(e.verifierNom))
	mux.HandleFunc("/api/nom/reserver", garde(e.reserverNom))
	mux.HandleFunc("/api/nom/attendre", garde(e.attendreConfirmation))
	mux.HandleFunc("/api/reglages", garde(e.enregistrerReglages))
	mux.HandleFunc("/api/installer", garde(e.lancerInstallation))
	mux.HandleFunc("/api/fermer", garde(e.fermer))
}

func (e *Etat) repond(w http.ResponseWriter, corps any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(corps)
}

func (e *Etat) lireEtat(w http.ResponseWriter, _ *http.Request) {
	e.mu.Lock()
	copie := struct {
		Etape          string     `json:"etape"`
		Erreur         string     `json:"erreur"`
		Journal        []string   `json:"journal"`
		Docker         DockerEtat `json:"docker"`
		Prerequis      Prerequis  `json:"prerequis"`
		Reseau         Diagnostic `json:"reseau"`
		Nom            string     `json:"nom"`
		Courriel       string     `json:"courriel"`
		Adresse        string     `json:"adresse"`
		DossierMusique string     `json:"dossierMusique"`
		DossierServeur string     `json:"dossierServeur"`
		Utilisateur    string     `json:"utilisateur"`
		Progression    int        `json:"progression"`
	}{
		Etape: e.Etape, Erreur: e.Erreur, Journal: e.Journal, Docker: e.Docker,
		Prerequis: e.Prerequis, Reseau: e.Reseau,
		Nom: e.Nom, Courriel: e.Courriel, Adresse: e.Adresse,
		DossierMusique: e.DossierMusique, DossierServeur: e.DossierServeur,
		Utilisateur: e.Utilisateur, Progression: e.Progression,
	}
	e.mu.Unlock()
	e.repond(w, copie)
}

func (e *Etat) fermer(w http.ResponseWriter, _ *http.Request) {
	e.repond(w, map[string]bool{"ok": true})
	e.ferme.Do(func() { close(e.fini) })
}

// ── Choisir un dossier ───────────────────────────────────────────────────────

// listerDossiers alimente le sélecteur de dossier de la page.
//
// Un sélecteur maison plutôt que la fenêtre du système : celle-ci se demande
// différemment sur chaque plateforme (zenity, PowerShell, osascript), dépend de
// ce qui est installé, et ne peut pas être essayée automatiquement. Ici, le
// même code sert partout et se vérifie.
func (e *Etat) listerDossiers(w http.ResponseWriter, r *http.Request) {
	chemin := r.URL.Query().Get("chemin")
	if chemin == "" {
		maison, err := os.UserHomeDir()
		if err != nil {
			maison = "/"
		}
		chemin = maison
	}
	chemin = filepath.Clean(chemin)

	entrees, err := os.ReadDir(chemin)
	if err != nil {
		e.repond(w, map[string]any{
			"erreur": fmt.Sprintf("Ce dossier ne s'ouvre pas : %v", err),
			"chemin": chemin,
		})
		return
	}

	var dossiers []string
	for _, entree := range entrees {
		if !entree.IsDir() || strings.HasPrefix(entree.Name(), ".") {
			continue // les dossiers cachés n'intéressent personne ici
		}
		dossiers = append(dossiers, entree.Name())
	}
	sort.Strings(dossiers)

	parent := filepath.Dir(chemin)
	if parent == chemin {
		parent = "" // on est à la racine
	}

	e.repond(w, map[string]any{
		"chemin":   chemin,
		"parent":   parent,
		"dossiers": dossiers,
	})
}

// ── Les réglages (dossier de musique et compte) ──────────────────────────────

func (e *Etat) enregistrerReglages(w http.ResponseWriter, r *http.Request) {
	var corps struct {
		DossierMusique string `json:"dossierMusique"`
		DossierServeur string `json:"dossierServeur"`
		Utilisateur    string `json:"utilisateur"`
		MotDePasse     string `json:"motDePasse"`
	}
	if err := json.NewDecoder(r.Body).Decode(&corps); err != nil {
		e.repond(w, map[string]string{"erreur": "Je n'ai pas compris la demande."})
		return
	}

	if message := verifieDossierMusique(corps.DossierMusique); message != "" {
		e.repond(w, map[string]string{"erreur": message})
		return
	}
	if len(strings.TrimSpace(corps.Utilisateur)) < 2 {
		e.repond(w, map[string]string{"erreur": "Choisis un nom d'utilisateur d'au moins deux lettres."})
		return
	}
	if len(corps.MotDePasse) < 8 {
		e.repond(w, map[string]string{"erreur": "Le mot de passe doit faire au moins huit caractères."})
		return
	}

	e.mu.Lock()
	e.DossierMusique = filepath.Clean(corps.DossierMusique)
	if strings.TrimSpace(corps.DossierServeur) != "" {
		e.DossierServeur = filepath.Clean(corps.DossierServeur)
	}
	e.Utilisateur = strings.TrimSpace(corps.Utilisateur)
	e.motDePasse = corps.MotDePasse
	e.mu.Unlock()

	e.avance("installation")
	e.repond(w, map[string]bool{"ok": true})
}

// verifieDossierMusique dit, en français, pourquoi un dossier ne convient pas.
//
// On vérifie aussi qu'on peut y ÉCRIRE : le serveur y déposera les
// téléchargements, et s'en apercevoir après l'installation serait trop tard.
func verifieDossierMusique(chemin string) string {
	if strings.TrimSpace(chemin) == "" {
		return "Choisis le dossier où vit ta musique."
	}
	info, err := os.Stat(chemin)
	if err != nil {
		return "Ce dossier n'existe pas (ou n'est pas lisible)."
	}
	if !info.IsDir() {
		return "Ce n'est pas un dossier."
	}

	essai := filepath.Join(chemin, ".gullify-essai-ecriture")
	f, err := os.Create(essai)
	if err != nil {
		return "Ce dossier est en lecture seule : le serveur ne pourrait pas y ranger les téléchargements."
	}
	_ = f.Close()
	_ = os.Remove(essai)
	return ""
}
