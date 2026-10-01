package main

import (
	"context"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

// Ce que Windows doit avoir AVANT Docker.
//
// Docker Desktop ne tourne pas sur une machine où la virtualisation est
// éteinte. Il le dit à sa façon — « Virtualization support not detected », avec
// une invitation à se connecter à un compte qui n'a rien à voir — et quelqu'un
// qui ne sait pas de quoi il s'agit reste planté là.
//
// Deux obstacles bien distincts se cachent derrière ce message, et ils ne se
// règlent pas au même endroit :
//
//   la virtualisation est éteinte dans le FIRMWARE : cela se rallume au
//   démarrage de l'ordinateur, dans le BIOS. Aucun programme ne peut le faire à
//   la place de son propriétaire ;
//
//   le composant Windows manque : « Plateforme de machine virtuelle » et WSL.
//   Celui-là, on sait l'installer — une commande, un redémarrage.
//
// Les confondre, c'est envoyer quelqu'un fouiller son BIOS alors qu'une
// commande suffisait, ou l'inverse.

type Prerequis struct {
	Verifie    bool   `json:"verifie"`
	Virtualise bool   `json:"virtualise"` // le processeur y est autorisé par le firmware
	WSL        bool   `json:"wsl"`        // le sous-système Linux est là
	Bloquant   bool   `json:"bloquant"`   // rien ne servira tant que ce n'est pas réglé
	Reparable  bool   `json:"reparable"`  // on sait le faire nous-mêmes
	Explique   string `json:"explique"`   //
	Marche     string `json:"marche"`     // la marche à suivre, si elle est manuelle
}

// regardePrerequis n'a de sens que sous Windows ; ailleurs, Docker se suffit.
func regardePrerequis() Prerequis {
	if runtime.GOOS != "windows" {
		return Prerequis{Verifie: true, Virtualise: true, WSL: true}
	}

	p := Prerequis{Verifie: true}
	p.Virtualise = vraiDePowerShell(
		"(Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled")

	// Un hyperviseur déjà présent prouve que la virtualisation fonctionne, même
	// si le premier test reste muet (il l'est sur certaines machines).
	if !p.Virtualise {
		p.Virtualise = vraiDePowerShell("(Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent")
	}

	p.WSL = commandeReussit("wsl", "--status")

	switch {
	case !p.Virtualise:
		p.Bloquant = true
		p.Explique = "La virtualisation est éteinte sur cet ordinateur. Docker ne peut " +
			"pas fonctionner sans elle, et personne ne peut la rallumer depuis Windows : " +
			"cela se passe au démarrage de la machine."
		p.Marche = "À faire une seule fois :\n" +
			"1. Redémarre l'ordinateur et, pendant qu'il démarre, appuie plusieurs fois\n" +
			"   sur la touche d'entrée dans le BIOS — souvent Suppr, F2, F10 ou F12\n" +
			"   (l'écran de démarrage l'indique une seconde).\n" +
			"2. Cherche « Virtualization », « SVM Mode » (AMD) ou « Intel VT-x » (Intel),\n" +
			"   souvent dans Advanced, CPU Configuration ou Overclocking.\n" +
			"3. Mets-le sur Enabled.\n" +
			"4. Enregistre et quitte (souvent F10), laisse Windows démarrer,\n" +
			"   puis relance ce programme."

	case !p.WSL:
		p.Bloquant = true
		p.Reparable = true
		p.Explique = "Il manque à Windows le composant qui fait tourner Linux (WSL), " +
			"dont Docker a besoin. Je peux l'installer : il faudra redémarrer une fois."

	default:
		p.Explique = "Cet ordinateur a tout ce qu'il faut."
	}

	return p
}

// installeWSL pose le composant manquant. Windows demandera l'autorisation, et
// réclamera un redémarrage.
func (e *Etat) installeWSL() error {
	e.dit("Installation du composant Linux de Windows (WSL)…")
	e.majProgresDocker("Installation de WSL… (Windows va demander ton autorisation)")

	ctx, annule := context.WithTimeout(context.Background(), 20*time.Minute)
	defer annule()

	// --no-distribution : Docker apporte la sienne. Sans cette option, Windows
	// installerait Ubuntu par-dessus, que personne n'a demandé.
	sortie, err := exec.CommandContext(ctx, "wsl", "--install", "--no-distribution").CombinedOutput()
	for _, ligne := range dernieresLignes(string(sortie), 6) {
		e.dit("  %s", ligne)
	}
	e.majProgresDocker("")

	if err != nil {
		return err
	}
	e.dit("WSL est posé. Redémarre l'ordinateur, puis relance ce programme.")
	return nil
}

// ── Deux façons de poser une question à Windows ──────────────────────────────

func vraiDePowerShell(expression string) bool {
	ctx, annule := context.WithTimeout(context.Background(), 20*time.Second)
	defer annule()

	sortie, err := exec.CommandContext(ctx, "powershell", "-NoProfile", "-NonInteractive",
		"-Command", expression).Output()
	if err != nil {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(string(sortie)), "True")
}

func commandeReussit(nom string, args ...string) bool {
	ctx, annule := context.WithTimeout(context.Background(), 20*time.Second)
	defer annule()
	return exec.CommandContext(ctx, nom, args...).Run() == nil
}

// reparerPrerequis : le point d'entrée de la page, pour ce qu'on sait réparer.
func (e *Etat) reparerPrerequis(w http.ResponseWriter, _ *http.Request) {
	p := regardePrerequis()
	if !p.Reparable {
		e.repond(w, map[string]any{"lance": false, "prerequis": p})
		return
	}
	go func() {
		if err := e.installeWSL(); err != nil {
			e.echoue("L'installation du composant Linux a échoué (%v).", err)
		}
	}()
	e.repond(w, map[string]any{"lance": true})
}
