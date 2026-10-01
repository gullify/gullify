package main

import (
	"context"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

// DockerEtat : ce qu'on sait de Docker sur cette machine.
type DockerEtat struct {
	Installe bool   `json:"installe"` // le programme existe
	Demarre  bool   `json:"demarre"`  // et il répond
	Version  string `json:"version"`  //
	Compose  bool   `json:"compose"`  // « docker compose » est disponible
	Commande string `json:"commande"` // ce qu'il faut taper pour l'installer
	Explique string `json:"explique"` // ce qu'on dit à l'écran
	Verifie  bool   `json:"verifie"`  // la vérification a eu lieu
}

// regardeDocker ne modifie rien : il observe et raconte.
func regardeDocker() DockerEtat {
	etat := DockerEtat{Verifie: true}

	chemin, err := exec.LookPath("docker")
	if err != nil {
		etat.Commande, etat.Explique = commandeInstallation()
		return etat
	}
	etat.Installe = true

	// `docker info` échoue si le service n'est pas démarré : c'est le cas le
	// plus courant sur Windows et macOS, où Docker Desktop doit être lancé.
	ctx, annule := context.WithTimeout(context.Background(), 20*time.Second)
	defer annule()
	if err := exec.CommandContext(ctx, chemin, "info", "--format", "{{.ServerVersion}}").Run(); err != nil {
		etat.Explique = "Docker est installé mais ne tourne pas. Lance Docker Desktop, attends qu'il soit vert, puis reviens ici."
		if runtime.GOOS == "linux" {
			etat.Explique = "Docker est installé mais ne tourne pas. Essaie : sudo systemctl start docker"
		}
		return etat
	}
	etat.Demarre = true

	if sortie, err := exec.CommandContext(ctx, chemin, "version", "--format", "{{.Server.Version}}").Output(); err == nil {
		etat.Version = strings.TrimSpace(string(sortie))
	}

	// Docker Compose v2 est un sous-programme : « docker compose », pas
	// « docker-compose ». On vérifie celui-là, c'est lui qu'on emploiera.
	if err := exec.CommandContext(ctx, chemin, "compose", "version").Run(); err == nil {
		etat.Compose = true
	} else {
		etat.Explique = "Docker tourne, mais sans « docker compose ». Mets Docker à jour : c'est inclus depuis plusieurs versions."
	}

	return etat
}

// commandeInstallation rend la façon d'installer Docker sur ce système, et le
// texte qui va avec.
//
// L'installateur propose de la lancer, mais ne la lance jamais en douce : poser
// un logiciel de cette taille sur la machine de quelqu'un se demande.
func commandeInstallation() (commande string, explique string) {
	switch runtime.GOOS {
	case "windows":
		return "winget install -e --id Docker.DockerDesktop",
			"Docker n'est pas là. Je peux l'installer pour toi (environ 600 Mo). " +
				"Windows demandera une confirmation, et il faudra redémarrer l'ordinateur une fois."
	case "darwin":
		return "brew install --cask docker",
			"Docker n'est pas là. Si tu as Homebrew, je peux l'installer pour toi. " +
				"Sinon, télécharge Docker Desktop depuis docker.com, puis reviens ici."
	default:
		return "curl -fsSL https://get.docker.com | sh",
			"Docker n'est pas là. Je peux l'installer (la commande demandera ton mot de passe)."
	}
}

// ── Les points d'entrée ──────────────────────────────────────────────────────

func (e *Etat) verifierDocker(w http.ResponseWriter, _ *http.Request) {
	etat := regardeDocker()

	e.mu.Lock()
	e.Docker = etat
	e.mu.Unlock()

	switch {
	case etat.Demarre && etat.Compose:
		e.dit("Docker %s est prêt.", etat.Version)
	case etat.Installe:
		e.dit("Docker est là mais pas prêt.")
	default:
		e.dit("Docker n'est pas installé.")
	}

	e.repond(w, etat)
}

// installerDocker lance la commande du système et rend la main tout de suite :
// l'installation peut durer, la page suit le journal.
func (e *Etat) installerDocker(w http.ResponseWriter, _ *http.Request) {
	commande, _ := commandeInstallation()
	e.dit("Installation de Docker : %s", commande)

	go func() {
		var cmd *exec.Cmd
		if runtime.GOOS == "windows" {
			cmd = exec.Command("cmd", "/C", commande)
		} else {
			cmd = exec.Command("sh", "-c", commande)
		}

		sortie, err := cmd.CombinedOutput()
		for _, ligne := range dernieresLignes(string(sortie), 8) {
			e.dit("  %s", ligne)
		}
		if err != nil {
			e.echoue("L'installation de Docker a échoué. Installe-le toi-même depuis docker.com, puis reviens.")
			return
		}
		e.dit("Docker est installé. Je vérifie…")

		etat := regardeDocker()
		e.mu.Lock()
		e.Docker = etat
		e.mu.Unlock()
		if !etat.Demarre {
			e.dit("Il reste à le démarrer : %s", etat.Explique)
		}
	}()

	e.repond(w, map[string]bool{"lance": true})
}

// dernieresLignes garde la fin d'une sortie de commande : c'est là que se
// trouve ce qui a échoué, et la page n'a pas la place pour le reste.
func dernieresLignes(texte string, combien int) []string {
	var lignes []string
	for _, l := range strings.Split(strings.TrimSpace(texte), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			lignes = append(lignes, l)
		}
	}
	if len(lignes) > combien {
		lignes = lignes[len(lignes)-combien:]
	}
	return lignes
}
