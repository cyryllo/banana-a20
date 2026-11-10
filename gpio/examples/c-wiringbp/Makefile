# Build the WiringBP examples (install WiringBP first: cd ../../WiringBP && ./build).
CFLAGS ?= -O2 -Wall
LDLIBS  = -lwiringPi -lpthread -lm -lcrypt -lrt

PROGRAMS = blink button_isr soft_pwm

all: $(PROGRAMS)

clean:
	rm -f $(PROGRAMS)
