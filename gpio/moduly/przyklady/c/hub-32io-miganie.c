/*
 * hub-32io-miganie.c: 32 diody LN HUB-32IO migaja, potem "wedrujace swiatlo".
 *
 * CO: dwa uklady MCP23017 na I2C (adresy 0x20 i 0x21) daja 32 wyjscia z diodami.
 * Na podstawie expansion_boards_demo/LN_HUB_32IO.c (LeMaker, 2015).
 *
 * Kompilacja: gcc -Wall -o hub-32io-miganie hub-32io-miganie.c -lwiringPi
 * Uruchomienie: sudo ./hub-32io-miganie
 * I2C2 (piny 3 i 5) jest wlaczone w Armbianie domyslnie; WiringBP sam znajduje
 * jego /dev/i2c-N po adresie kontrolera (1c2b400).
 */
#include <stdio.h>
#include <wiringPi.h>
#include <mcp23017.h>

// CO: piny 100-115 = uklad 0x20, 200-215 = uklad 0x21.
#define BAZA1 100
#define BAZA2 200

static int pin (int n) { return n < 16 ? BAZA1 + n : BAZA2 + n - 16; }

int main (void)
{
	int i, n;

	wiringPiSetup ();
	if (mcp23017Setup (BAZA1, 0x20) < 0 || mcp23017Setup (BAZA2, 0x21) < 0) {
		fprintf (stderr, "Brak dostepu do I2C (sudo?)\n");
		return 1;
	}
	for (n = 0; n < 32; ++n)
		pinMode (pin (n), OUTPUT);

	printf ("LN HUB-32IO: wszystkie diody migaja 3 razy\n");
	for (i = 0; i < 3; ++i) {
		for (n = 0; n < 32; ++n)
			digitalWrite (pin (n), 1);
		delay (500);
		for (n = 0; n < 32; ++n)
			digitalWrite (pin (n), 0);
		delay (500);
	}
	printf ("LN HUB-32IO: wedrujace swiatlo\n");
	for (n = 0; n < 32; ++n) {
		digitalWrite (pin (n), 1);
		delay (80);
		digitalWrite (pin (n), 0);
	}
	printf ("Gotowe\n");
	return 0;
}
