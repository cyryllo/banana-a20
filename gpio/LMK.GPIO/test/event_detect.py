import LMK.GPIO as GPIO
import time

#The following pins support the external event detected on the 40Pin Header of the LeMake Guitar
'''P8 P10 P12 P13 P15 P16 P22 P19 P23'''

#The following pins support the external event detected on the 40Pin Header of the BananaPro
'''P7 P8 P10 P11 P13 P15 P16 P18 P19 P21 P22 P23 P24 P26'''

testPinOnGt = 8   #For LeMaker Guitar
testPinonBP = 18  #For BananaPro

GPIO.setmode(GPIO.BOARD)

def testEventDetect(pin, trigger):
	switchCnt = 0	
	GPIO.setup(pin, GPIO.IN, GPIO.PUD_UP)

	GPIO.add_event_detect(pin, trigger)

	while switchCnt < 2:   
		if GPIO.event_detected(pin):
			switchCnt += 1
			print 'The event has been detected'
			print "\n value_%d = %d\n" %(pin,GPIO.input(pin))

	GPIO.remove_event_detect(pin)

testEventDetect(testPinOnGt, GPIO.RISING)  # add rising edge detection on a channel

GPIO.cleanup()
