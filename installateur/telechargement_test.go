package main

import (
	"fmt"
	"strings"
	"testing"
)

// La barre d'avancement : c'est elle qu'on regarde pendant dix minutes, et
// c'est elle qui a menti deux fois ce soir. Qu'au moins elle compte juste.
func TestAvancement(t *testing.T) {
	cas := []struct {
		quoi          string
		recu, total   int64
		contient      []string
		neContientPas []string
	}{
		{
			quoi:     "au départ",
			recu:     0,
			total:    600 << 20,
			contient: []string{"0 %", "0 Mo", "600 Mo", "░"},
		},
		{
			quoi:     "à mi-chemin",
			recu:     300 << 20,
			total:    600 << 20,
			contient: []string{"50 %", "300 Mo", "█", "░"},
		},
		{
			quoi:          "à la fin",
			recu:          600 << 20,
			total:         600 << 20,
			contient:      []string{"100 %", "600 Mo"},
			neContientPas: []string{"░"}, // la barre est pleine
		},
		{
			quoi:          "quand la taille est inconnue",
			recu:          42 << 20,
			total:         -1,
			contient:      []string{"42 Mo"},
			neContientPas: []string{"%"}, // on n'invente pas un pourcentage
		},
	}

	for _, c := range cas {
		t.Run(c.quoi, func(t *testing.T) {
			ligne := avancement(c.recu, c.total)
			for _, attendu := range c.contient {
				if !strings.Contains(ligne, attendu) {
					t.Errorf("« %s » devrait contenir %q", ligne, attendu)
				}
			}
			for _, interdit := range c.neContientPas {
				if strings.Contains(ligne, interdit) {
					t.Errorf("« %s » ne devrait pas contenir %q", ligne, interdit)
				}
			}
		})
	}
}

// La barre fait toujours vingt caractères : une barre qui change de longueur
// fait sauter la mise en page à chaque rafraîchissement.
func TestBarreDeLongueurConstante(t *testing.T) {
	for pourcent := 0; pourcent <= 100; pourcent += 7 {
		ligne := avancement(int64(pourcent)*(1<<20), 100<<20)
		barre := strings.Count(ligne, "█") + strings.Count(ligne, "░")
		if barre != 20 {
			t.Errorf("à %d %% : %d caractères de barre, attendu 20 (%s)", pourcent, barre, ligne)
		}
	}
}

func TestEnMo(t *testing.T) {
	cas := map[int64]string{
		0:          "0 Mo",
		1 << 20:    "1 Mo",
		627791792:  "599 Mo", // la vraie taille du programme de Docker
		1500 << 20: "1500 Mo",
	}
	for octets, attendu := range cas {
		if obtenu := enMo(octets); obtenu != attendu {
			t.Errorf("%d octets → %s, attendu %s", octets, obtenu, attendu)
		}
	}
}

func TestRepete(t *testing.T) {
	if r := repete("█", 3); r != "███" {
		t.Errorf("repete(█, 3) = %q", r)
	}
	// Une valeur négative ne doit pas faire paniquer : elle arrive si un
	// serveur annonce une taille plus petite que ce qu'il envoie.
	if r := repete("█", -5); r != "" {
		t.Errorf("repete(█, -5) = %q, attendu vide", r)
	}
	_ = fmt.Sprint()
}
