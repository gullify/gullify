// L'installateur de GulliFY : un seul fichier à double-cliquer, qui pose un
// serveur de musique chez soi.
//
// Il n'a pas d'interface à lui. Il démarre un petit serveur web sur la machine,
// ouvre le navigateur dessus, et c'est le navigateur qui fait l'écran — avec
// l'habillage de gullify.app, celui que les gens verront ensuite dans l'app.
// Trois raisons à ce choix : une seule interface à dessiner et à maintenir, un
// rendu identique sur les trois systèmes, et un binaire qui se compile depuis
// n'importe quelle machine (pas besoin d'un Mac pour fabriquer la version Mac).
//
// Compilation : voir construire.sh
package main

import (
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os/exec"
	"runtime"
	"time"
)

//go:embed web
var pages embed.FS

func main() {
	service := flag.String("service", "https://gullify.app",
		"l'adresse du service qui distribue les sous-domaines (pour les essais)")
	port := flag.Int("port", 0, "le port local (0 = au hasard)")
	sansNavigateur := flag.Bool("sans-navigateur", false, "ne pas ouvrir le navigateur")
	flag.Parse()

	// Le jeton de session : il voyage dans l'adresse et dans chaque appel.
	// Sans lui, n'importe quel site ouvert dans le même navigateur pourrait
	// piloter l'installation — il tourne sur 127.0.0.1, mais une page web
	// peut parler à 127.0.0.1.
	jeton := hasard(16)

	etat := NouvelEtat(*service)

	racine, err := fs.Sub(pages, "web")
	if err != nil {
		log.Fatalf("pages introuvables : %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/", sansCache(http.FileServer(http.FS(racine))))
	etat.Router(mux, jeton)

	ecoute, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		log.Fatalf("impossible d'ouvrir un port local : %v", err)
	}
	adresse := fmt.Sprintf("http://%s/?cle=%s", ecoute.Addr().String(), jeton)

	fmt.Println()
	fmt.Println("  GulliFY — installation")
	fmt.Println()
	fmt.Println("  Si rien ne s'ouvre, copie cette adresse dans ton navigateur :")
	fmt.Println("  " + adresse)
	fmt.Println()

	if !*sansNavigateur {
		ouvrirNavigateur(adresse)
	}

	serveur := &http.Server{Handler: journalise(mux)}

	// L'installateur s'arrête quand la page le demande (bouton « Fermer ») ou
	// quand on l'interrompt au clavier.
	go func() {
		<-etat.Fini()
		ctx, annule := context.WithTimeout(context.Background(), 3*time.Second)
		defer annule()
		_ = serveur.Shutdown(ctx)
	}()

	if err := serveur.Serve(ecoute); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("le serveur local s'est arrêté : %v", err)
	}
	fmt.Println("  Fermé.")
}

// hasard rend une chaîne hexadécimale imprévisible de n octets.
func hasard(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// Sans source d'aléa, mieux vaut s'arrêter que de poser un jeton devinable.
		log.Fatalf("pas de source d'aléa : %v", err)
	}
	return hex.EncodeToString(b)
}

// ouvrirNavigateur fait de son mieux ; s'il échoue, l'adresse reste affichée
// dans la console et l'installation se poursuit à la main.
func ouvrirNavigateur(adresse string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", adresse)
	case "darwin":
		cmd = exec.Command("open", adresse)
	default:
		cmd = exec.Command("xdg-open", adresse)
	}
	if err := cmd.Start(); err != nil {
		log.Printf("impossible d'ouvrir le navigateur (%v) — ouvre l'adresse à la main", err)
	}
}

// sansCache interdit au navigateur de garder la page.
//
// L'installateur ouvre un port au hasard, mais rien ne garantit qu'il soit
// différent d'une fois sur l'autre : le navigateur peut alors resservir la page
// d'une version précédente, et l'on croit corriger un défaut qui reste à
// l'écran. Ces fichiers sont minuscules et lus une seule fois — rien à gagner à
// les garder.
func sansCache(suivant http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, must-revalidate")
		w.Header().Set("Pragma", "no-cache")
		suivant.ServeHTTP(w, r)
	})
}

// journalise écrit les appels dans la console, qui sert de journal en cas de
// pépin : c'est ce que les gens copieront pour demander de l'aide.
func journalise(suivant http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		debut := time.Now()
		suivant.ServeHTTP(w, r)
		if r.URL.Path != "/api/etat" { // inutile : la page le demande en boucle
			log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(debut).Round(time.Millisecond))
		}
	})
}
