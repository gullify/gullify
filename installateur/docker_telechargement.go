package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// Installer Docker sous Windows, nous-mêmes, du début à la fin.
//
// (Le fichier ne s'appelle PAS docker_windows.go : Go y verrait une contrainte
// de compilation et ne le garderait que pour Windows — il ne compilerait plus
// ailleurs. Le choix du système se fait à l'appel, dans docker.go.)
//
// La première version passait par `winget`. Deux échecs de suite l'ont
// condamnée : il pose des questions à un terminal que personne ne regarde, et
// une fois les privilèges élevés il poursuit dans un autre processus, hors de
// portée. Impossible de savoir ce qui se passe, ni de le montrer.
//
// Ici, on fait le travail : on télécharge le programme officiel de Docker —
// donc on compte les octets, et la barre d'avancement dit la vérité — puis on
// le lance en mode silencieux. Une seule interruption pour la personne : la
// demande d'administrateur de Windows, qu'elle reconnaît.

// L'adresse officielle de Docker Desktop pour Windows. Elle sert la dernière
// version ; Docker ne la numérote pas dans le chemin.
const dockerWindowsURL = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"

// En deçà, ce n'est pas le programme mais une page d'erreur déguisée.
const dockerTailleMinimale = 100 << 20 // 100 Mo

// installeDockerWindows télécharge puis installe, en racontant ce qu'il fait.
func (e *Etat) installeDockerWindows() {
	fichier := filepath.Join(os.TempDir(), "DockerDesktopInstaller.exe")

	e.dit("Téléchargement de Docker Desktop (environ 600 Mo).")
	if err := e.telecharge(dockerWindowsURL, fichier); err != nil {
		e.majProgresDocker("")
		e.echoue("Le téléchargement de Docker a échoué : %v", err)
		return
	}

	e.dit("Téléchargement terminé. J'installe — Windows va demander ton autorisation.")
	e.majProgresDocker("Installation en cours… (réponds « Oui » à la fenêtre de Windows)")

	// `install --quiet --accept-license` : les options du programme officiel.
	// Le programme exige lui-même les droits d'administrateur ; c'est Windows
	// qui ouvre la demande, et la personne la reconnaît.
	cmd := exec.Command(fichier, "install", "--quiet", "--accept-license")
	if sortie, err := cmd.CombinedOutput(); err != nil {
		e.majProgresDocker("")
		for _, ligne := range dernieresLignes(string(sortie), 6) {
			e.dit("  %s", ligne)
		}
		e.echoue("L'installation de Docker s'est arrêtée. Si tu as refusé la demande " +
			"de Windows, reclique sur « Installer Docker ».")
		return
	}

	_ = os.Remove(fichier) // 600 Mo n'ont rien à faire dans le dossier temporaire

	e.dit("Docker est installé. Je le démarre.")
	e.majProgresDocker("Docker démarre… (le premier démarrage prend une minute ou deux)")
	demarreDockerWindows()

	// À partir d'ici, une seule chose compte : Docker répond-il ?
	e.guetteDocker(20 * time.Minute)
}

// telecharge écrit le fichier en annonçant l'avancement.
//
// C'est tout l'intérêt de faire le téléchargement soi-même : on compte les
// octets, donc la barre ne ment pas. Les vingt minutes de « téléchargement »
// immobile qui ont précédé venaient justement de ce qu'on affichait un
// avancement qu'on ne mesurait pas.
func (e *Etat) telecharge(adresse, destination string) error {
	client := &http.Client{Timeout: 45 * time.Minute}
	reponse, err := client.Get(adresse)
	if err != nil {
		return fmt.Errorf("connexion impossible (%w)", err)
	}
	defer reponse.Body.Close()

	if reponse.StatusCode != http.StatusOK {
		return fmt.Errorf("le serveur de Docker a répondu %d", reponse.StatusCode)
	}

	total := reponse.ContentLength
	if total > 0 && total < dockerTailleMinimale {
		return fmt.Errorf("le fichier reçu est trop petit (%d octets) pour être Docker", total)
	}

	sortie, err := os.Create(destination)
	if err != nil {
		return fmt.Errorf("impossible d'écrire dans le dossier temporaire (%w)", err)
	}
	defer sortie.Close()

	var recu int64
	tampon := make([]byte, 256<<10)
	dernierDit := time.Now()

	for {
		n, err := reponse.Body.Read(tampon)
		if n > 0 {
			if _, err := sortie.Write(tampon[:n]); err != nil {
				return fmt.Errorf("écriture impossible (%w)", err)
			}
			recu += int64(n)

			// Deux fois par seconde : assez pour que ça vive, pas assez pour
			// noyer la page d'appels.
			if time.Since(dernierDit) > 500*time.Millisecond {
				dernierDit = time.Now()
				e.majProgresDocker(avancement(recu, total))
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("téléchargement interrompu après %s (%w)", enMo(recu), err)
		}
	}

	if recu < dockerTailleMinimale {
		return fmt.Errorf("le fichier reçu ne fait que %s — ce n'est pas Docker", enMo(recu))
	}

	e.majProgresDocker(fmt.Sprintf("Téléchargé : %s", enMo(recu)))
	return nil
}

func avancement(recu, total int64) string {
	if total <= 0 {
		return fmt.Sprintf("Téléchargé : %s", enMo(recu))
	}
	pourcent := int(recu * 100 / total)
	barres := pourcent / 5
	return fmt.Sprintf("[%s%s] %d %%  —  %s sur %s",
		repete("█", barres), repete("░", 20-barres), pourcent, enMo(recu), enMo(total))
}

func repete(motif string, combien int) string {
	if combien < 0 {
		combien = 0
	}
	sortie := ""
	for i := 0; i < combien; i++ {
		sortie += motif
	}
	return sortie
}

func enMo(octets int64) string {
	return fmt.Sprintf("%.0f Mo", float64(octets)/(1<<20))
}

// demarreDockerWindows lance Docker Desktop : installé ne veut pas dire en
// marche, et c'est le service qui compte.
func demarreDockerWindows() {
	chemins := []string{
		`C:\Program Files\Docker\Docker\Docker Desktop.exe`,
		filepath.Join(os.Getenv("ProgramFiles"), `Docker\Docker\Docker Desktop.exe`),
	}
	for _, chemin := range chemins {
		if _, err := os.Stat(chemin); err == nil {
			_ = exec.Command(chemin).Start()
			return
		}
	}
}
