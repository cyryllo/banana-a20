/*
 * ln-digital-przyciski.c: przyciski S1-S4 przelaczaja wyjscia LN Digital.
 *
 * CO: kazde nacisniecie przycisku n przelacza wyjscia 2n i 2n+1
 *     (S1: P0 i P1 = przekazniki K1 i K2, jesli zalozone JP5/JP6).
 *     Ctrl+C konczy program.
 * Na podstawie expansion_boards_demo/LN_DIGITAL.c (LeMaker, 2015), ktory
 * wywodzi sie z przykladu buttons.c z WiringPi (Gordon Henderson, LGPL-3.0).
 *
 * Kompilacja: gcc -Wall -o ln-digital-przyciski ln-digital-przyciski.c -lwiringPi -lwiringPiDev
 * Uruchomienie: sudo ./ln-digital-przyciski
 */
#include <stdio.h>
#include <unistd.h>
#include <wiringPi.h>
#include <piFace.h>

// CO: piFaceSetup: BAZA+0..7 przy zapisie = wyjscia P0-P7, przy odczycie = wejscia IN0-IN7.
#define BAZA 200

static int stan[4];

static void sprawdz_przycisk (int n)
{
	if (digitalRead (BAZA + n) != LOW)
		return;
	stan[n] ^= 1;
	digitalWrite (BAZA + 2 * n, stan[n]);
	digitalWrite (BAZA + 2 * n + 1, stan[n]);
	printf ("Przycisk S%d: wyjscia P%d i P%d %s\n", n + 1, 2 * n, 2 * n + 1, stan[n] ? "wlaczone" : "wylaczone");
	// DLACZEGO czekanie na puszczenie: jedno nacisniecie = jedno przelaczenie.
	while (digitalRead (BAZA + n) == LOW)
		delay (1);
	delay (20);
}

int main (void)
{
	int i;

	// CO: najpierw sprawdzenie SPI.
	// DLACZEGO: funkcje WiringBP nie zwracaja czytelnego bledu, gdy nie ma /dev/spidev0.0.
	if (access ("/dev/spidev0.0", R_OK | W_OK) != 0) {
		fprintf (stderr, "Brak dostepu do /dev/spidev0.0: wlacz nakladke spi-spidev (param_spidev_spi_bus=0) i uruchom przez sudo\n");
		return 1;
	}
	wiringPiSetup ();
	piFaceSetup (BAZA);
	for (i = 0; i < 8; ++i) {
		pullUpDnControl (BAZA + i, PUD_UP);
		digitalWrite (BAZA + i, 0);
	}
	printf ("LN Digital: naciskaj S1-S4, Ctrl+C konczy\n");
	for (;;) {
		for (i = 0; i < 4; ++i)
			sprawdz_przycisk (i);
		delay (5);
	}
	return 0;
}
