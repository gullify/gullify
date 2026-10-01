package main

import "testing"

// Le verdict réseau, cas par cas.
//
// Ces situations ne se reproduisent pas sur une machine de développement : il
// faudrait un vrai routeur qui obéit, un autre qui refuse, et un abonnement
// dont l'opérateur partage l'adresse. D'où ces essais : la règle est écrite une
// fois, et vérifiée sur les quatre réseaux qu'on rencontre pour de bon.
func TestConclut(t *testing.T) {
	cas := []struct {
		quoi      string
		locale    string
		publique  string
		ipRouteur string
		upnp      bool

		verdict string
		cgnat   bool
		marche  bool // on attend une marche à suivre
	}{
		{
			quoi:     "une machine directement sur Internet (hébergeur)",
			locale:   "87.106.149.41",
			publique: "87.106.149.41",
			verdict:  "ouvert",
		},
		{
			quoi:      "une maison ordinaire, routeur coopératif",
			locale:    "192.168.1.42",
			publique:  "24.48.72.96",
			ipRouteur: "24.48.72.96",
			upnp:      true,
			verdict:   "ferme", // en attente de l'ouverture, qui est possible
		},
		{
			quoi:     "une maison dont le routeur refuse d'obéir",
			locale:   "192.168.1.42",
			publique: "24.48.72.96",
			upnp:     false,
			verdict:  "ferme",
			marche:   true,
		},
		{
			quoi:      "un réseau d'opérateur, reconnu à la plage partagée",
			locale:    "192.168.1.42",
			publique:  "24.48.72.96",
			ipRouteur: "100.73.12.4",
			upnp:      true,
			verdict:   "cgnat",
			cgnat:     true,
			marche:    true,
		},
		{
			quoi:      "un réseau d'opérateur masqué : le routeur a une autre adresse publique",
			locale:    "192.168.1.42",
			publique:  "24.48.72.96",
			ipRouteur: "203.0.113.9",
			upnp:      true,
			verdict:   "cgnat",
			cgnat:     true,
			marche:    true,
		},
		{
			// Sans ce cas, retirer la reconnaissance de la plage partagée ne
			// casserait rien : ailleurs, « l'adresse diffère » suffit à
			// conclure. Ici les deux adresses sont identiques et partagées —
			// seule la plage trahit l'opérateur.
			quoi:      "un réseau d'opérateur où les deux adresses sont partagées",
			locale:    "192.168.1.42",
			publique:  "100.73.12.4",
			ipRouteur: "100.73.12.4",
			upnp:      true,
			verdict:   "cgnat",
			cgnat:     true,
			marche:    true,
		},
		{
			// L'ordre des tests compte : un abonné en réseau d'opérateur DONT
			// le routeur refuse aussi l'UPnP doit s'entendre dire que c'est
			// sans espoir — pas recevoir une marche à suivre qui ne marchera
			// jamais.
			quoi:      "réseau d'opérateur ET routeur fermé : le premier prime",
			locale:    "192.168.1.42",
			publique:  "24.48.72.96",
			ipRouteur: "100.73.12.4",
			upnp:      false,
			verdict:   "cgnat",
			cgnat:     true,
			marche:    true,
		},
		{
			quoi:      "un routeur muet sur son adresse : on ne crie pas au loup",
			locale:    "192.168.1.42",
			publique:  "24.48.72.96",
			ipRouteur: "", // GetExternalIPAddress a échoué
			upnp:      true,
			verdict:   "ferme",
		},
	}

	for _, c := range cas {
		t.Run(c.quoi, func(t *testing.T) {
			d := conclut(c.locale, c.publique, c.ipRouteur, c.upnp)

			if d.Verdict != c.verdict {
				t.Errorf("verdict = %q, attendu %q (%s)", d.Verdict, c.verdict, d.Explique)
			}
			if d.CGNAT != c.cgnat {
				t.Errorf("cgnat = %v, attendu %v", d.CGNAT, c.cgnat)
			}
			if (d.Marche != "") != c.marche {
				t.Errorf("marche à suivre = %v, attendue %v", d.Marche != "", c.marche)
			}
			if d.Explique == "" {
				t.Error("un verdict sans explication : l'écran n'aurait rien à montrer")
			}
		})
	}
}

// La plage partagée des opérateurs : 100.64.0.0 à 100.127.255.255. Ses bornes
// comptent — 100.63 et 100.128 sont des adresses publiques ordinaires, et les
// confondre ferait annoncer un réseau d'opérateur à quelqu'un qui n'en a pas.
func TestPartagee(t *testing.T) {
	dedans := []string{"100.64.0.0", "100.73.12.4", "100.127.255.255"}
	dehors := []string{"100.63.255.255", "100.128.0.1", "24.48.72.96", "192.168.1.1", "", "pas une adresse"}

	for _, ip := range dedans {
		if !partagee(ip) {
			t.Errorf("%s devrait être reconnue comme partagée", ip)
		}
	}
	for _, ip := range dehors {
		if partagee(ip) {
			t.Errorf("%s ne devrait PAS être reconnue comme partagée", ip)
		}
	}
}

// L'adresse probable du routeur, qu'on affiche dans la marche à suivre.
func TestPasserelleProbable(t *testing.T) {
	cas := map[string]string{
		"192.168.1.42":   "http://192.168.1.1",
		"10.0.0.17":      "http://10.0.0.1",
		"172.16.31.200":  "http://172.16.31.1",
		"n'importe quoi": "192.168.1.1", // repli : mieux vaut une piste qu'un vide
	}
	for locale, attendu := range cas {
		if obtenu := passerelleProbable(locale); obtenu != attendu {
			t.Errorf("pour %s : %s, attendu %s", locale, obtenu, attendu)
		}
	}
}
