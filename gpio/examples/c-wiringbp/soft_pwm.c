/*
 * soft_pwm.c - fade an LED in and out with software PWM.
 *
 * Wiring: LED + 330 ohm resistor on physical pin 11 (PI19), as in blink.c.
 * Build:  make            Run: sudo ./soft_pwm
 *
 * softPwm works on any pin (a background thread switches it on and off),
 * good for LEDs, not precise enough for servos. For a real hardware PWM use
 * pin 12 (PWM1) with the Armbian "pwm" overlay, see the README.
 */
#include <stdio.h>
#include <wiringPi.h>
#include <softPwm.h>

#define LED 0      /* wPi 0 = physical pin 11 */

int main (void)
{
  int round, level ;

  if (wiringPiSetup () < 0)
    return 1 ;

  softPwmCreate (LED, 0, 100) ;      /* range 0..100 = percent */
  for (round = 0 ; round < 3 ; ++round)
  {
    for (level = 0 ; level <= 100 ; ++level) { softPwmWrite (LED, level) ; delay (10) ; }
    for (level = 100 ; level >= 0 ; --level) { softPwmWrite (LED, level) ; delay (10) ; }
  }
  softPwmStop (LED) ;
  pinMode (LED, INPUT) ;
  printf ("done\n") ;
  return 0 ;
}
