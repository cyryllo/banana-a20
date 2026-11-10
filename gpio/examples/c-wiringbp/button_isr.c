/*
 * button_isr.c - react to a button with an interrupt (no busy polling).
 *
 * Wiring: push button between physical pin 13 (PI18) and GND (pin 14),
 *         optional LED on pin 11 as in blink.c (toggles on each press).
 * Build:  make            Run: sudo ./button_isr   (Ctrl+C to stop)
 *
 * The internal pull-up keeps the pin HIGH, a press pulls it LOW, so we wait
 * for the falling edge. Only some header pins can raise interrupts, see the
 * pinout (yellow kernel GPIO numbers).
 */
#include <stdio.h>
#include <wiringPi.h>

#define LED    0   /* wPi 0 = physical pin 11 */
#define BUTTON 2   /* wPi 2 = physical pin 13 */

static volatile int presses = 0 ;
static unsigned int last = 0 ;

/* Runs in a separate thread for every falling edge. */
static void pressed (void)
{
  unsigned int now = millis () ;
  if (now - last < 200)              /* simple debounce: ignore bounces < 200 ms */
    return ;
  last = now ;
  ++presses ;
  digitalWrite (LED, presses & 1) ;
  printf ("press %d\n", presses) ;
  fflush (stdout) ;
}

int main (void)
{
  if (wiringPiSetup () < 0)
    return 1 ;

  pinMode (LED, OUTPUT) ;
  pinMode (BUTTON, INPUT) ;
  pullUpDnControl (BUTTON, PUD_UP) ;

  if (wiringPiISR (BUTTON, INT_EDGE_FALLING, &pressed) < 0)
  {
    fprintf (stderr, "cannot set up the interrupt\n") ;
    return 1 ;
  }
  printf ("waiting for the button on pin 13, Ctrl+C to stop\n") ;
  for (;;)
    delay (1000) ;                   /* the work happens in pressed() */
}
