/*
 * ln-io.c: test plytki LN IO (LeMaker) przez WiringBP.
 *
 * Uzycie: sudo ./ln-io diody|przyciski|lcd|i2c|spi|uart
 *   diody      8 diod (wPi 0-7), zworki CN1 w pozycji LED
 *   przyciski  4 przyciski KEY (wPi 2-5), zworki H11; 15 s odczytu
 *   lcd        LCD 1602 w zlaczu H13, 8 bitow, zworki CN1 w pozycji LCD
 *   i2c        przetwornik PCF8591 (adres 0x48) w zlaczu I2C
 *   spi        pamiec AT45DB041D w zlaczu SPI (CE0): zapis i odczyt bajtu
 *   uart       mostek UART: H2 TX <-> H3 RX7 i H2 RX <-> H3 TX7
 *
 * Na podstawie expansion_boards_demo/LN_IO_BOARD.c (LeMaker, 2014), poprawione
 * dla obecnego jadra: nazwy portow szeregowych z adresu kontrolera, bez
 * "gpio load spi", bez konfliktu przyciskow z diodami na wPi 2-5.
 *
 * Kompilacja: gcc -Wall -o ln-io ln-io.c -lwiringPi -lwiringPiDev
 */
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wiringPi.h>
#include <wiringPiSPI.h>
#include <wiringSerial.h>
#include <pcf8591.h>
#include <lcd.h>

#define PCF_BAZA 100

// CO: piny LN IO w numeracji wPi (taka sama jak na schemacie: GPIO0..GPIO7).
static const int DIODY[8] = { 0, 1, 2, 3, 4, 5, 6, 7 };
static const int PRZYCISKI[4] = { 2, 3, 4, 5 };

static void diody (void)
{
	int i, n;

	for (i = 0; i < 8; ++i)
		pinMode (DIODY[i], OUTPUT);
	printf ("Diody: wedrujace swiatlo, potem 3 razy wszystkie\n");
	for (i = 0; i < 8; ++i) {
		digitalWrite (DIODY[i], HIGH);
		delay (150);
		digitalWrite (DIODY[i], LOW);
	}
	for (n = 0; n < 3; ++n) {
		for (i = 0; i < 8; ++i)
			digitalWrite (DIODY[i], HIGH);
		delay (400);
		for (i = 0; i < 8; ++i)
			digitalWrite (DIODY[i], LOW);
		delay (400);
	}
}

// DLACZEGO tylko wejscia z podciaganiem: przyciski zwieraja pin do GND. Oryginalny
// test LeMakera ustawial te same piny jako wyjscia w stanie wysokim (diody), a
// przycisk zwieral wtedy wyjscie do masy; tu przyciski i diody na wPi 2-5 sie wykluczaja.
static void przyciski (void)
{
	int i, poprz[4], teraz;
	unsigned int koniec;

	for (i = 0; i < 4; ++i) {
		pinMode (PRZYCISKI[i], INPUT);
		pullUpDnControl (PRZYCISKI[i], PUD_UP);
	}
	delay (20);
	for (i = 0; i < 4; ++i)
		poprz[i] = digitalRead (PRZYCISKI[i]);
	printf ("Przyciski: naciskaj przez 15 s (zworki diod na wPi 2-5 zdjete)\n");
	koniec = millis () + 15000;
	while (millis () < koniec) {
		for (i = 0; i < 4; ++i) {
			teraz = digitalRead (PRZYCISKI[i]);
			if (teraz != poprz[i] && teraz == LOW)
				printf ("Przycisk %d (wPi %d) nacisniety\n", i + 1, PRZYCISKI[i]);
			poprz[i] = teraz;
		}
		delay (10);
	}
}

static void lcd (void)
{
	// CO: 2 wiersze, 16 znakow, 8 bitow; RS = wPi 21 (pin 29, PB3), E = wPi 23 (pin 33, PB13), dane wPi 0-7.
	int h = lcdInit (2, 16, 8, 21, 23, 0, 1, 2, 3, 4, 5, 6, 7);
	if (h < 0) {
		fprintf (stderr, "LCD: lcdInit nie powiodlo sie\n");
		return;
	}
	lcdClear (h);
	lcdPosition (h, 0, 0);
	lcdPuts (h, "Banana Pro");
	lcdPosition (h, 0, 1);
	lcdPuts (h, "LN IO: LCD OK");
	printf ("LCD: na ekranie powinno byc \"Banana Pro\" / \"LN IO: LCD OK\" (kontrast: potencjometr R2)\n");
}

static void i2c (void)
{
	int k;

	if (pcf8591Setup (PCF_BAZA, 0x48) < 0) {
		fprintf (stderr, "I2C: brak PCF8591 pod adresem 0x48\n");
		return;
	}
	analogWrite (PCF_BAZA, 128);
	printf ("I2C: wyjscie analogowe ustawione na 128/255 (ok. 1,65 V przy 3,3 V), zmierz je\n");
	for (k = 0; k < 4; ++k)
		printf ("I2C: wejscie analogowe %d = %d (0-255)\n", k, analogRead (PCF_BAZA + k));
}

static void spi (void)
{
	// CO: AT45DB041D: zapis bajtu do bufora 1 (0x84) i odczyt z bufora 1 (0xD4), adres 2.
	unsigned char zapis[5] = { 0x84, 0x00, 0x00, 0x02, 0x34 };
	unsigned char odczyt[6] = { 0xD4, 0x00, 0x00, 0x02, 0xff, 0xff };

	if (access ("/dev/spidev0.0", R_OK | W_OK) != 0) {
		fprintf (stderr, "SPI: brak /dev/spidev0.0 (nakladka spi-spidev, param_spidev_spi_bus=0)\n");
		return;
	}
	if (wiringPiSPISetup (0, 5000000) < 0) {
		fprintf (stderr, "SPI: nie mozna otworzyc /dev/spidev0.0\n");
		return;
	}
	wiringPiSPIDataRW (0, zapis, sizeof zapis);
	delay (10);
	wiringPiSPIDataRW (0, odczyt, sizeof odczyt);
	printf ("SPI: zapisano 0x34, odczytano 0x%02x: %s\n", odczyt[5], odczyt[5] == 0x34 ? "OK" : "BLAD");
}

// CO: /dev/ttySn kontrolera o danym adresie (np. "1c29000").
// DLACZEGO po adresie: numery ttyS zaleza od jadra (stare sunxi 3.4: ttyS2/ttyS3,
// obecny Armbian: UART4 = ttyS1, UART7 = ttyS2).
static int tty_po_adresie (const char *adres, char *wynik, size_t n)
{
	char sciezka[64], cel[PATH_MAX];
	int i;

	for (i = 0; i < 8; ++i) {
		snprintf (sciezka, sizeof sciezka, "/sys/class/tty/ttyS%d/device", i);
		if (realpath (sciezka, cel) && strstr (cel, adres)) {
			snprintf (wynik, n, "/dev/ttyS%d", i);
			return 0;
		}
	}
	return -1;
}

static int przeslij (int z, int do_, int znak)
{
	serialFlush (do_);
	serialPutchar (z, znak);
	delay (100);
	return serialDataAvail (do_) > 0 && serialGetchar (do_) == znak;
}

static void uart (void)
{
	char u4[16], u7[16];
	int f4, f7;

	if (tty_po_adresie ("1c29000", u4, sizeof u4) || tty_po_adresie ("1c29c00", u7, sizeof u7)) {
		fprintf (stderr, "UART: brak UART4 albo UART7 w systemie\n");
		return;
	}
	if ((f4 = serialOpen (u4, 115200)) < 0 || (f7 = serialOpen (u7, 115200)) < 0) {
		fprintf (stderr, "UART: nie mozna otworzyc %s / %s: %s\n", u4, u7, strerror (errno));
		return;
	}
	printf ("UART: %s (H2, piny 8/10) <-> %s (H3, piny 31/32)\n", u4, u7);
	printf ("UART: UART4 -> UART7: %s\n", przeslij (f4, f7, 't') ? "OK" : "BLAD");
	printf ("UART: UART7 -> UART4: %s\n", przeslij (f7, f4, 'r') ? "OK" : "BLAD");
	serialClose (f4);
	serialClose (f7);
}

int main (int argc, char **argv)
{
	if (argc != 2) {
		fprintf (stderr, "Uzycie: sudo %s diody|przyciski|lcd|i2c|spi|uart\n", argv[0]);
		return 1;
	}
	wiringPiSetup ();
	if (!strcmp (argv[1], "diody")) diody ();
	else if (!strcmp (argv[1], "przyciski")) przyciski ();
	else if (!strcmp (argv[1], "lcd")) lcd ();
	else if (!strcmp (argv[1], "i2c")) i2c ();
	else if (!strcmp (argv[1], "spi")) spi ();
	else if (!strcmp (argv[1], "uart")) uart ();
	else {
		fprintf (stderr, "Nieznane: %s (diody|przyciski|lcd|i2c|spi|uart)\n", argv[1]);
		return 1;
	}
	return 0;
}
