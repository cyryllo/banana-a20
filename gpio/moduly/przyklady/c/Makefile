# CO: buduje przyklady modulow LeMaker; wymaga pakietu wiringbp (biblioteki i naglowki).
CFLAGS ?= -O2 -Wall
LDLIBS = -lwiringPi -lwiringPiDev -lpthread -lm
PROGRAMY = ln-digital-test ln-digital-przyciski hub-32io-miganie ln-io

all: $(PROGRAMY)

clean:
	rm -f $(PROGRAMY)

.PHONY: all clean
