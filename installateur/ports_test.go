package main

import (
	"net"
	"os"
	"runtime"
	"strconv"
	"testing"
)

func TestPortOccupeQuandUnProgrammeEcoute(t *testing.T) {
	ecoute, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Fatal(err)
	}
	defer ecoute.Close()
	port := strconv.Itoa(ecoute.Addr().(*net.TCPAddr).Port)
	if !portOccupe(port) {
		t.Errorf("le port %s est pris, portOccupe dit libre", port)
	}
}

func TestPortLibre(t *testing.T) {
	ecoute, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Fatal(err)
	}
	port := strconv.Itoa(ecoute.Addr().(*net.TCPAddr).Port)
	ecoute.Close()
	if portOccupe(port) {
		t.Errorf("le port %s est libre, portOccupe dit pris", port)
	}
}

// Sous Linux, un compte ordinaire ne peut pas écouter sur un port privilégié :
// ce refus ne doit pas passer pour « port pris ».
func TestPortPrivilegieLibreSansEtreRoot(t *testing.T) {
	if runtime.GOOS != "linux" || os.Geteuid() == 0 {
		t.Skip("seulement sous Linux, sans être root")
	}
	if b, err := os.ReadFile("/proc/sys/net/ipv4/ip_unprivileged_port_start"); err != nil || string(b) != "1024\n" {
		t.Skip("ports privilégiés non standards sur cette machine")
	}
	if _, err := net.Dial("tcp", "127.0.0.1:1"); err == nil {
		t.Skip("quelque chose écoute sur le port 1")
	}
	if portOccupe("1") {
		t.Error("le port 1 est libre mais interdit : portOccupe le dit pris")
	}
}
