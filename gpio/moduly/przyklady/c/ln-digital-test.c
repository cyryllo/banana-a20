/*
 * ln-digital-test.c: LN Digital (LeMaker, klon PiFace) przez WiringBP.
 *
 * CO: zapala po kolei 8 wyjsc (diody P0-P7, na P0 i P1 przekazniki, jesli
 *     zalozone zworki JP5/JP6), gasi je w odwrotnej kolejnosci, potem
 *     odczytuje 8 wejsc (IN0-IN3 = przyciski S1-S4).
 * Na podstawie programu z bloga cyryllo.pl (2015), z poprawiona petla wejsc
 * (oryginalna petla "i > 16" nigdy sie nie wykonywala).
 *
 * Kompilacja: gcc -Wall -o ln-digital-test ln-digital-test.c -lwiringPi
 * Uruchomienie: sudo ./ln-digital-test
 * Wymaga SPI: nakladka spi-spidev i param_spidev_spi_bus=0 (/dev/spidev0.0).
 */
#include <stdio.h>
#include <unistd.h>
#include <wiringPi.h>
#include <mcp23s17.h>

// CO: numery pinow rozszerzenia: BAZA+0..7 = port A (wyjscia), BAZA+8..15 = port B (wejscia).
#define BAZA 100

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
	// DLACZEGO 0, 0: SPI0 z CE0 (/dev/spidev0.0), adres ukladu 0 (zworki JP1, JP2 w pozycji 0).
	mcp23s17Setup (BAZA, 0, 0);
	printf ("LN Digital: test wyjsc i wejsc\n");

	for (i = 0; i < 8; ++i)
		pinMode (BAZA + i, OUTPUT);
	for (i = 0; i < 8; ++i) {
		digitalWrite (BAZA + i, 1);
		delay (300);
	}
	delay (500);
	for (i = 7; i >= 0; --i) {
		digitalWrite (BAZA + i, 0);
		delay (300);
	}

	// CO: wejscia z wewnetrznym podciaganiem; nacisniety przycisk = 0.
	for (i = 8; i < 16; ++i) {
		pinMode (BAZA + i, INPUT);
		pullUpDnControl (BAZA + i, PUD_UP);
	}
	for (i = 8; i < 16; ++i)
		printf ("Wejscie IN%d: %d\n", i - 8, digitalRead (BAZA + i));
	return 0;
}
