package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Le dialogue avec le service d'inscription de gullify.app : réserver un nom,
// attendre la confirmation par courriel, puis annoncer son adresse IP.

type reponseService struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data"`
	Error   *struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// appelService parle au service et rend les données, ou un message d'erreur
// déjà écrit pour être lu par un humain — c'est le service qui les rédige.
func (e *Etat) appelService(methode, action string, parametres url.Values, corps any, resultat any) error {
	adresse := fmt.Sprintf("%s/api/v2/registry.php?action=%s", e.service, action)
	if len(parametres) > 0 {
		adresse += "&" + parametres.Encode()
	}

	var lecteur io.Reader
	if corps != nil {
		encode, err := json.Marshal(corps)
		if err != nil {
			return fmt.Errorf("je n'ai pas pu préparer la demande : %w", err)
		}
		lecteur = bytes.NewReader(encode)
	}

	requete, err := http.NewRequest(methode, adresse, lecteur)
	if err != nil {
		return fmt.Errorf("adresse du service invalide : %w", err)
	}
	requete.Header.Set("Content-Type", "application/json")
	requete.Header.Set("User-Agent", "GullifyInstallateur/1.0")

	client := &http.Client{Timeout: 25 * time.Second}
	reponse, err := client.Do(requete)
	if err != nil {
		return fmt.Errorf("gullify.app ne répond pas. Vérifie ta connexion à Internet.")
	}
	defer reponse.Body.Close()

	var enveloppe reponseService
	if err := json.NewDecoder(reponse.Body).Decode(&enveloppe); err != nil {
		return fmt.Errorf("gullify.app a répondu quelque chose d'incompréhensible (code %d)", reponse.StatusCode)
	}
	if !enveloppe.Success {
		if enveloppe.Error != nil {
			return fmt.Errorf("%s", enveloppe.Error.Message)
		}
		return fmt.Errorf("le service a refusé la demande (code %d)", reponse.StatusCode)
	}
	if resultat != nil && len(enveloppe.Data) > 0 {
		if err := json.Unmarshal(enveloppe.Data, resultat); err != nil {
			return fmt.Errorf("réponse inattendue du service : %w", err)
		}
	}
	return nil
}

// ── Le nom ───────────────────────────────────────────────────────────────────

func (e *Etat) verifierNom(w http.ResponseWriter, r *http.Request) {
	nom := strings.TrimSpace(r.URL.Query().Get("nom"))

	// Chaque champ compte : ce qui n'est pas déclaré ici est PERDU, puisque la
	// réponse est recopiée depuis cette structure. « reprenable » y manquait,
	// et la page ne pouvait donc pas proposer de reprendre un nom — elle
	// affichait pourtant le message du service, qui l'y invitait.
	var resultat struct {
		Nom        string `json:"nom"`
		Libre      bool   `json:"libre"`
		Reprenable bool   `json:"reprenable"`
		Motif      string `json:"motif"`
		Adresse    string `json:"adresse"`
	}
	if err := e.appelService("GET", "disponible", url.Values{"nom": {nom}}, nil, &resultat); err != nil {
		e.repond(w, map[string]any{"libre": false, "motif": err.Error()})
		return
	}
	e.repond(w, resultat)
}

func (e *Etat) reserverNom(w http.ResponseWriter, r *http.Request) {
	var corps struct {
		Nom      string `json:"nom"`
		Courriel string `json:"courriel"`
	}
	if err := json.NewDecoder(r.Body).Decode(&corps); err != nil {
		e.repond(w, map[string]string{"erreur": "Je n'ai pas compris la demande."})
		return
	}

	var resultat struct {
		Reservation string `json:"reservation"`
	}
	if err := e.appelService("POST", "reserver", nil, corps, &resultat); err != nil {
		e.repond(w, map[string]string{"erreur": err.Error()})
		return
	}

	e.mu.Lock()
	e.Nom = strings.ToLower(strings.TrimSpace(corps.Nom))
	e.Courriel = corps.Courriel
	e.Reservation = resultat.Reservation
	e.mu.Unlock()

	e.dit("Nom réservé : %s. Un courriel est parti vers %s.", e.Nom, corps.Courriel)
	e.avance("confirmation")
	e.repond(w, map[string]bool{"ok": true})
}

// attendreConfirmation est appelée en boucle par la page pendant que la
// personne va voir ses courriels.
func (e *Etat) attendreConfirmation(w http.ResponseWriter, _ *http.Request) {
	e.mu.Lock()
	reservation := e.Reservation
	dejaJeton := e.Jeton != ""
	e.mu.Unlock()

	if reservation == "" {
		e.repond(w, map[string]any{"confirme": false, "erreur": "Aucune réservation en cours."})
		return
	}
	if dejaJeton {
		// Le jeton n'est remis qu'une fois par le service : une fois qu'on
		// l'a, on arrête de demander.
		e.repond(w, map[string]any{"confirme": true})
		return
	}

	var resultat struct {
		State string `json:"state"`
		Fqdn  string `json:"fqdn"`
		Token string `json:"token"`
	}
	if err := e.appelService("GET", "etat", url.Values{"reservation": {reservation}}, nil, &resultat); err != nil {
		e.repond(w, map[string]any{"confirme": false, "erreur": err.Error()})
		return
	}

	if resultat.State != "active" || resultat.Token == "" {
		e.repond(w, map[string]any{"confirme": false})
		return
	}

	e.mu.Lock()
	e.Jeton = resultat.Token
	e.Adresse = resultat.Fqdn
	e.mu.Unlock()

	e.dit("Adresse confirmée : %s", resultat.Fqdn)
	e.avance("reglages")
	e.repond(w, map[string]any{"confirme": true, "adresse": resultat.Fqdn})
}

// annonceIP dit au service « me voici », pour que le nom pointe sur cette
// maison. L'adresse n'est pas envoyée : le service prend celle d'où l'appel
// arrive, c'est ce qui empêche de publier l'adresse d'un autre.
func (e *Etat) annonceIP() error {
	e.mu.Lock()
	jeton := e.Jeton
	e.mu.Unlock()

	if jeton == "" {
		return fmt.Errorf("aucun jeton : le nom n'a pas été confirmé")
	}

	var resultat struct {
		Fqdn    string `json:"fqdn"`
		IP      string `json:"ip"`
		Changed bool   `json:"changed"`
	}
	if err := e.appelService("POST", "ip", nil, map[string]string{"jeton": jeton}, &resultat); err != nil {
		return err
	}
	e.dit("%s pointe sur %s.", resultat.Fqdn, resultat.IP)
	return nil
}

// signale raconte au service ce qui a cloché, pour qu'on sache — en chiffres —
// ce qui empêche les gens d'installer. Sans jamais interrompre l'installation :
// un incident qu'on n'arrive pas à signaler reste un incident mineur.
func (e *Etat) signale(genre, detail string) {
	e.mu.Lock()
	nom := e.Nom
	e.mu.Unlock()

	go func() {
		_ = e.appelService("POST", "incident", nil, map[string]string{
			"genre":  genre,
			"detail": detail,
			"nom":    nom,
		}, nil)
	}()
}
