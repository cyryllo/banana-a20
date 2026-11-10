/*
 * blink.c - blink an LED with WiringBP.
 *
 * Wiring: LED + 330 ohm resistor from physical pin 11 (PI19) to GND (pin 9).
 * Build:  make            Run: sudo ./blink
 *
 * wiringPiSetup() uses wPi numbers: wPi 0 = physical pin 11.
 * wiringPiSetupPhys() would let you use the physical number (11) instead.
 */
#include <stdio.h>
#include <wiringPi.h>

#define LED 0   /* wPi 0 = physical pin 11 = PI19 */

int main (void)
{
  int i ;

  if (wiringPiSetup () < 0)          /* needs root: it maps the GPIO registers */
    return 1 ;

  pinMode (LED, OUTPUT) ;
  for (i = 0 ; i < 10 ; ++i)
  {
    digitalWrite (LED, HIGH) ; printf ("on\n") ;  delay (500) ;
    digitalWrite (LED, LOW) ;  printf ("off\n") ; delay (500) ;
  }
  pinMode (LED, INPUT) ;             /* leave the pin safe (input) at the end */
  return 0 ;
}
