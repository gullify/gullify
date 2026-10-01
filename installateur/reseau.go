package main

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Le réseau de la maison : trouver le routeur, lui demander d'ouvrir les ports,
// et savoir dire quand c'est impossible.
//
// C'est la partie qui décide si un serveur de salon est joignable depuis
// l'extérieur. Trois choses peuvent clocher, et il faut les distinguer : le
// routeur refuse d'obéir (UPnP désactivé), le routeur obéit mais son adresse
// n'est pas publique (réseau d'opérateur — rien n'y fera), ou tout va bien mais
// un pare-feu bloque encore. Un message qui mélangerait les trois ferait perdre
// des heures à des gens qui n'y peuvent rien.

// Diagnostic : ce qu'on a compris du réseau, en français, prêt pour l'écran.
type Diagnostic struct {
	Fait         bool   `json:"fait"`
	IPLocale     string `json:"ipLocale"`     // l'adresse de cette machine sur le réseau
	IPPublique   string `json:"ipPublique"`   // celle que le monde voit
	IPRouteur    string `json:"ipRouteur"`    // celle que le routeur croit avoir
	Routeur      string `json:"routeur"`      // le modèle, s'il le dit
	UPnP         bool   `json:"upnp"`         // le routeur accepte qu'on lui parle
	PortsOuverts bool   `json:"portsOuverts"` // l'ouverture a réussi
	CGNAT        bool   `json:"cgnat"`        // l'opérateur partage l'adresse
	Verdict      string `json:"verdict"`      // « ouvert », « ferme », « cgnat », « inconnu »
	Explique     string `json:"explique"`     // ce qu'on dit à l'écran
	Marche       string `json:"marche"`       // la marche à suivre, si elle existe
}

// ── L'adresse de cette machine ───────────────────────────────────────────────

// adresseLocale rend l'adresse par laquelle cette machine sort vers Internet.
//
// Aucun paquet n'est envoyé : ouvrir une socket UDP ne fait que demander au
// système quelle route il emprunterait. C'est la façon fiable d'obtenir la
// bonne adresse sur une machine qui en a plusieurs (Wi-Fi, câble, machines
// virtuelles, Docker).
func adresseLocale() (string, error) {
	conn, err := net.Dial("udp", "1.1.1.1:80")
	if err != nil {
		return "", fmt.Errorf("impossible de déterminer l'adresse de cette machine : %w", err)
	}
	defer conn.Close()
	return conn.LocalAddr().(*net.UDPAddr).IP.String(), nil
}

// partagee dit si une adresse appartient à la plage 100.64.0.0/10, celle que
// les opérateurs emploient quand ils partagent une adresse publique entre
// plusieurs abonnés. Une adresse de cette plage ne peut PAS recevoir de
// connexion entrante, et aucun réglage n'y changera quoi que ce soit.
func partagee(ip string) bool {
	adresse := net.ParseIP(ip)
	if adresse == nil {
		return false
	}
	_, plage, _ := net.ParseCIDR("100.64.0.0/10")
	return plage.Contains(adresse)
}

// ── Trouver le routeur ───────────────────────────────────────────────────────

// routeur : de quoi parler à la passerelle de la maison.
type routeur struct {
	controle string // l'adresse où envoyer les ordres
	service  string // le nom du service (il en existe plusieurs variantes)
	modele   string // ce que le routeur dit de lui-même
}

// cherchePasserelle interroge le réseau local et attend que la passerelle se
// présente.
//
// Le protocole : un message en diffusion sur 239.255.255.250:1900, auquel les
// appareils répondent avec l'adresse de leur description. On accepte les trois
// variantes de service qui existent dans la nature ; un routeur n'en expose
// qu'une, et elle n'est pas la même selon l'âge et la marque.
func cherchePasserelle(patience time.Duration) (*routeur, error) {
	types := []string{
		"urn:schemas-upnp-org:device:InternetGatewayDevice:1",
		"urn:schemas-upnp-org:service:WANIPConnection:1",
		"urn:schemas-upnp-org:service:WANPPPConnection:1",
	}

	conn, err := net.ListenPacket("udp4", ":0")
	if err != nil {
		return nil, fmt.Errorf("impossible d'écouter sur le réseau local : %w", err)
	}
	defer conn.Close()

	destination := &net.UDPAddr{IP: net.IPv4(239, 255, 255, 250), Port: 1900}
	for _, t := range types {
		message := "M-SEARCH * HTTP/1.1\r\n" +
			"HOST: 239.255.255.250:1900\r\n" +
			"MAN: \"ssdp:discover\"\r\n" +
			"MX: 2\r\n" +
			"ST: " + t + "\r\n\r\n"
		_, _ = conn.WriteTo([]byte(message), destination)
	}

	_ = conn.SetReadDeadline(time.Now().Add(patience))
	vus := map[string]bool{}

	for {
		tampon := make([]byte, 2048)
		n, _, err := conn.ReadFrom(tampon)
		if err != nil {
			return nil, fmt.Errorf("aucun routeur ne répond")
		}

		emplacement := entete(string(tampon[:n]), "LOCATION")
		if emplacement == "" || vus[emplacement] {
			continue
		}
		vus[emplacement] = true

		if r, err := litLaDescription(emplacement); err == nil {
			return r, nil
		}
	}
}

// entete lit une en-tête d'une réponse SSDP, sans se soucier de la casse.
func entete(reponse, nom string) string {
	for _, ligne := range strings.Split(reponse, "\r\n") {
		if cle, valeur, ok := strings.Cut(ligne, ":"); ok {
			if strings.EqualFold(strings.TrimSpace(cle), nom) {
				return strings.TrimSpace(valeur)
			}
		}
	}
	return ""
}

// litLaDescription va chercher la fiche du routeur et y trouve le service qui
// sait ouvrir des ports.
func litLaDescription(emplacement string) (*routeur, error) {
	client := &http.Client{Timeout: 6 * time.Second}
	reponse, err := client.Get(emplacement)
	if err != nil {
		return nil, err
	}
	defer reponse.Body.Close()

	var fiche struct {
		Appareil struct {
			Modele   string `xml:"modelName"`
			Services []struct {
				Type     string `xml:"serviceType"`
				Controle string `xml:"controlURL"`
			} `xml:"serviceList>service"`
			Sous []struct {
				Services []struct {
					Type     string `xml:"serviceType"`
					Controle string `xml:"controlURL"`
				} `xml:"serviceList>service"`
				Sous []struct {
					Services []struct {
						Type     string `xml:"serviceType"`
						Controle string `xml:"controlURL"`
					} `xml:"serviceList>service"`
				} `xml:"deviceList>device"`
			} `xml:"deviceList>device"`
		} `xml:"device"`
	}

	corps, err := io.ReadAll(io.LimitReader(reponse.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if err := xml.Unmarshal(corps, &fiche); err != nil {
		return nil, err
	}

	// Le service qui nous intéresse est niché deux étages plus bas : la
	// passerelle contient un appareil « WAN », qui contient une « connexion ».
	var candidats []struct {
		Type     string `xml:"serviceType"`
		Controle string `xml:"controlURL"`
	}
	candidats = append(candidats, fiche.Appareil.Services...)
	for _, un := range fiche.Appareil.Sous {
		candidats = append(candidats, un.Services...)
		for _, deux := range un.Sous {
			candidats = append(candidats, deux.Services...)
		}
	}

	base, err := url.Parse(emplacement)
	if err != nil {
		return nil, err
	}

	for _, service := range candidats {
		if !strings.Contains(service.Type, "WANIPConnection") &&
			!strings.Contains(service.Type, "WANPPPConnection") {
			continue
		}
		adresse, err := base.Parse(service.Controle)
		if err != nil {
			continue
		}
		return &routeur{
			controle: adresse.String(),
			service:  service.Type,
			modele:   fiche.Appareil.Modele,
		}, nil
	}

	return nil, fmt.Errorf("ce routeur n'expose pas d'ouverture de ports")
}

// ── Lui donner des ordres ────────────────────────────────────────────────────

// ordonne envoie un ordre au routeur et rend sa réponse.
func (r *routeur) ordonne(action, corps string) (string, error) {
	enveloppe := `<?xml version="1.0"?>` +
		`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ` +
		`s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>` +
		`<u:` + action + ` xmlns:u="` + r.service + `">` + corps +
		`</u:` + action + `></s:Body></s:Envelope>`

	requete, err := http.NewRequest("POST", r.controle, bytes.NewBufferString(enveloppe))
	if err != nil {
		return "", err
	}
	requete.Header.Set("Content-Type", `text/xml; charset="utf-8"`)
	requete.Header.Set("SOAPAction", `"`+r.service+`#`+action+`"`)

	client := &http.Client{Timeout: 10 * time.Second}
	reponse, err := client.Do(requete)
	if err != nil {
		return "", fmt.Errorf("le routeur ne répond pas : %w", err)
	}
	defer reponse.Body.Close()

	lu, _ := io.ReadAll(io.LimitReader(reponse.Body, 1<<20))
	if reponse.StatusCode >= 400 {
		// Le routeur explique son refus dans le corps ; c'est là qu'on lit
		// « ConflictInMappingEntry » ou « ActionNotAuthorized ».
		return "", fmt.Errorf("refus du routeur (%d) : %s", reponse.StatusCode, extraitErreur(string(lu)))
	}
	return string(lu), nil
}

// extraitErreur sort le motif d'un refus UPnP, qui est enfoui dans du XML.
func extraitErreur(corps string) string {
	if _, apres, ok := strings.Cut(corps, "<errorDescription>"); ok {
		if motif, _, ok := strings.Cut(apres, "</errorDescription>"); ok {
			return motif
		}
	}
	return "motif non précisé"
}

// ipExterne demande au routeur l'adresse qu'il croit avoir côté Internet.
//
// C'est la mesure qui démasque un réseau d'opérateur : si le routeur annonce
// une adresse de la plage partagée, ou une adresse différente de celle que le
// monde voit, c'est qu'un second partage existe en amont — hors de portée.
func (r *routeur) ipExterne() (string, error) {
	reponse, err := r.ordonne("GetExternalIPAddress", "")
	if err != nil {
		return "", err
	}
	if _, apres, ok := strings.Cut(reponse, "<NewExternalIPAddress>"); ok {
		if ip, _, ok := strings.Cut(apres, "</NewExternalIPAddress>"); ok {
			return strings.TrimSpace(ip), nil
		}
	}
	return "", fmt.Errorf("le routeur n'a pas dit son adresse")
}

// ouvrePort demande au routeur de faire suivre un port vers cette machine.
//
// La durée est volontairement nulle : une ouverture permanente. Beaucoup de
// routeurs oublient les ouvertures temporaires à chaque redémarrage, et un
// serveur qui ne répond plus après une panne de courant serait pire que tout.
func (r *routeur) ouvrePort(port int, ipLocale string) error {
	corps := fmt.Sprintf(
		`<NewRemoteHost></NewRemoteHost><NewExternalPort>%d</NewExternalPort>`+
			`<NewProtocol>TCP</NewProtocol><NewInternalPort>%d</NewInternalPort>`+
			`<NewInternalClient>%s</NewInternalClient><NewEnabled>1</NewEnabled>`+
			`<NewPortMappingDescription>GulliFY</NewPortMappingDescription>`+
			`<NewLeaseDuration>0</NewLeaseDuration>`,
		port, port, ipLocale)

	_, err := r.ordonne("AddPortMapping", corps)
	return err
}

// ── Le diagnostic complet ────────────────────────────────────────────────────

// diagnostique enchaîne les mesures et rend un verdict en français.
//
// L'ordre compte : on cherche d'abord à savoir si la maison a une vraie adresse
// publique. Si elle n'en a pas, ouvrir des ports ne sert à rien et il vaut
// mieux le dire tout de suite — avant de faire télécharger un gigaoctet à
// quelqu'un dont le serveur ne sera jamais joignable.
func (e *Etat) diagnostique() Diagnostic {
	d := Diagnostic{Fait: true}

	locale, err := adresseLocale()
	if err != nil {
		d.Verdict, d.Explique = "inconnu", "Je n'arrive pas à voir le réseau de cette machine."
		return d
	}
	d.IPLocale = locale

	// Ce que le monde voit de cette connexion, demandé au service.
	var vue struct {
		IP string `json:"ip"`
	}
	if err := e.appelService("GET", "mon-ip", nil, nil, &vue); err != nil {
		d.Verdict = "inconnu"
		d.Explique = "Je n'arrive pas à joindre gullify.app pour savoir comment Internet te voit. " +
			"Vérifie ta connexion."
		return d
	}
	d.IPPublique = vue.IP

	// Le routeur, s'il veut bien se présenter. Ces deux mesures sont les seules
	// qui touchent au matériel ; tout le raisonnement qui suit est à part, et
	// se vérifie sans réseau (voir conclut et reseau_test.go).
	var ipRouteur, modele string
	upnp := false
	if passerelle, err := cherchePasserelle(4 * time.Second); err == nil {
		upnp = true
		modele = passerelle.modele
		if externe, err := passerelle.ipExterne(); err == nil {
			ipRouteur = externe
		}
	}

	d = conclut(locale, vue.IP, ipRouteur, upnp)
	d.Routeur = modele
	return d
}

// conclut tire le verdict des quatre mesures, et de rien d'autre.
//
// Séparée du reste à dessein : les cas qui comptent — un routeur qui obéit, un
// réseau d'opérateur — ne se reproduisent pas sur la machine où l'on développe.
// Isolée, la règle se vérifie cas par cas (reseau_test.go) au lieu d'être crue
// sur parole.
func conclut(locale, publique, ipRouteur string, upnp bool) Diagnostic {
	d := Diagnostic{
		Fait:       true,
		IPLocale:   locale,
		IPPublique: publique,
		IPRouteur:  ipRouteur,
		UPnP:       upnp,
	}

	// La machine est directement sur Internet (un hébergeur, pas une maison) :
	// il n'y a pas de routeur, et rien à ouvrir.
	if locale == publique {
		d.Verdict = "ouvert"
		d.Explique = "Cette machine est directement sur Internet : il n'y a aucun routeur à régler."
		return d
	}

	// Le réseau d'opérateur se reconnaît à ceci : le routeur n'a pas l'adresse
	// que le monde voit, ou il en a une de la plage partagée. Dans les deux cas
	// un second partage existe en amont, hors de portée — et aucune ouverture
	// de port n'y changera rien. Ce test passe AVANT celui de l'UPnP : un
	// routeur peut très bien obéir et rester inaccessible.
	if ipRouteur != "" && (partagee(ipRouteur) || ipRouteur != publique) {
		d.CGNAT = true
		d.Verdict = "cgnat"
		d.Explique = "Ton fournisseur d'accès partage une même adresse entre plusieurs abonnés " +
			"(ton routeur croit avoir " + ipRouteur + ", alors qu'Internet te voit en " + publique + "). " +
			"Aucun réglage ne peut rendre ton serveur joignable de l'extérieur."
		d.Marche = "Demande à ton fournisseur une adresse IP publique — c'est souvent gratuit, " +
			"parfois quelques dollars par mois. En attendant, ton serveur fonctionnera " +
			"parfaitement chez toi, sur ton réseau."
		return d
	}

	if !upnp {
		d.Verdict = "ferme"
		d.Explique = "Ton routeur ne se laisse pas configurer automatiquement (l'UPnP est " +
			"éteint, ou absent)."
		d.Marche = marcheASuivre(locale)
		return d
	}

	// Le routeur répond et son adresse est bien la nôtre : il ne reste qu'à lui
	// demander d'ouvrir.
	d.Verdict = "ferme"
	d.Explique = "Ton routeur répond et accepte d'être configuré. Je peux lui demander " +
		"d'ouvrir les ports 80 et 443 vers cette machine."
	return d
}

// ouvreLesPorts demande au routeur de faire suivre 80 et 443.
func (e *Etat) ouvreLesPorts() Diagnostic {
	d := e.diagnostique()
	if d.Verdict == "cgnat" || d.Verdict == "ouvert" || !d.UPnP {
		return d
	}

	passerelle, err := cherchePasserelle(4 * time.Second)
	if err != nil {
		d.Verdict = "ferme"
		d.Explique = "Le routeur ne répond plus."
		d.Marche = marcheASuivre(d.IPLocale)
		return d
	}

	for _, port := range []int{80, 443} {
		if err := passerelle.ouvrePort(port, d.IPLocale); err != nil {
			d.Verdict = "ferme"
			d.Explique = fmt.Sprintf("Ton routeur a refusé d'ouvrir le port %d (%v).", port, err)
			d.Marche = marcheASuivre(d.IPLocale)
			e.signale("routeur-refuse", err.Error())
			return d
		}
	}

	d.PortsOuverts = true
	d.Verdict = "ouvert"
	d.Explique = "Ton routeur a ouvert les ports 80 et 443 vers cette machine."
	return d
}

// marcheASuivre : les mots exacts à chercher dans l'interface d'un routeur,
// parce que chaque marque les nomme à sa façon.
func marcheASuivre(ipLocale string) string {
	return "À faire à la main, une seule fois :\n" +
		"1. Ouvre l'adresse de ton routeur dans un navigateur (souvent " + passerelleProbable(ipLocale) + ").\n" +
		"2. Cherche « Redirection de port », « Port forwarding » ou « NAT/PAT ».\n" +
		"3. Ajoute deux règles vers " + ipLocale + " : le port 80 et le port 443, en TCP.\n" +
		"4. Reviens ici et clique sur « Revérifier »."
}

// passerelleProbable devine l'adresse du routeur : le premier appareil du
// réseau, dans l'immense majorité des installations.
func passerelleProbable(ipLocale string) string {
	morceaux := strings.Split(ipLocale, ".")
	if len(morceaux) != 4 {
		return "192.168.1.1"
	}
	return fmt.Sprintf("http://%s.%s.%s.1", morceaux[0], morceaux[1], morceaux[2])
}

// ── Les points d'entrée ──────────────────────────────────────────────────────

func (e *Etat) verifierReseau(w http.ResponseWriter, _ *http.Request) {
	d := e.diagnostique()
	e.mu.Lock()
	e.Reseau = d
	e.mu.Unlock()
	e.dit("Réseau : %s", d.Explique)
	e.repond(w, d)
}

func (e *Etat) ouvrirLesPorts(w http.ResponseWriter, _ *http.Request) {
	d := e.ouvreLesPorts()
	e.mu.Lock()
	e.Reseau = d
	e.mu.Unlock()
	e.dit("Routeur : %s", d.Explique)
	e.repond(w, d)
}

// verifierJoignable demande au service d'essayer d'atteindre ce serveur depuis
// l'extérieur. C'est la seule preuve qui vaille : le serveur de salon, lui, ne
// peut pas savoir s'il est joignable.
func (e *Etat) verifierJoignable(w http.ResponseWriter, _ *http.Request) {
	e.mu.Lock()
	nom := e.Nom
	e.mu.Unlock()

	if nom == "" {
		e.repond(w, map[string]any{"joignable": false, "motif": "Le nom n'est pas encore réservé."})
		return
	}

	var resultat struct {
		Joignable bool            `json:"joignable"`
		Ports     map[string]bool `json:"ports"`
		IP        string          `json:"ip"`
		Motif     string          `json:"motif"`
	}
	if err := e.appelService("GET", "joignable", url.Values{"nom": {nom}}, nil, &resultat); err != nil {
		e.repond(w, map[string]any{"joignable": false, "motif": err.Error()})
		return
	}

	if !resultat.Joignable {
		e.signale("non-joignable", fmt.Sprintf("ports %v, ip %s", resultat.Ports, resultat.IP))
	}
	e.repond(w, resultat)
}
