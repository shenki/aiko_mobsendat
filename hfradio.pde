/* hfradio.pde
 * ~~~~~~~~~~~
 * Please do not remove the following notices.
 * License: GPLv3. http://geekscape.org/static/arduino_license.html
 * ----------------------------------------------------------------------------
 *
 * Requires:
 * PIN_ACCEL_SELECT: Accelerometer SPI select
 * byte accelBuffer[40][6];  //oversize so it doesn't overflow
 * byte accelSamples;  //points to last array element
 *
 * To Do
 * ~~~~~
 * - Check to see if we need to deselect the SPI bus between commands.
 */


#include <util/crc16.h>


#define     PIN_RTTY_SPACE      A2
#define     PIN_RTTY_MARK       A3
#define     PIN_RTTY_ENABLE     5
#define     ASCII_LENGTH        7
#define     RTTY_BAUD_RATE      300 // Not actually used at the moment

/* Timer2 reload value, globally available */  
unsigned int tcnt2;

// RTTY Flags and counters
boolean txLock = false; // Are we transmitting?
int current_tx_byte = 0; // What byte in rttyBuffer are we up to?
short current_byte_position; // Where in the byte are we?

// RTTY Text Buffer
char rttyBuffer[70];

// Sets the txLock flag, then copies the passed string into rttyBuffer.
// Also resets the counters.
// Can this be modified to dump the data on the end of the buffer if we haven't finished transmitting?
void rtty_txstring(char *string){
  if(txLock == false){
    strcpy(rttyBuffer, string);
    current_tx_byte = 0;
    current_byte_position = 0;
    txLock = true;
  }
}

// Sets up the pins and the interrupt to tick at 300 Hz.
void hfradioInitialize() {

    // Make sure all the pins are correct.
    pinMode(PIN_RTTY_MARK, OUTPUT);
    pinMode(PIN_RTTY_SPACE, OUTPUT);
    pinMode(PIN_RTTY_ENABLE, OUTPUT);

    digitalWrite(PIN_RTTY_ENABLE, HIGH);

    TIMSK2 &= ~(1<<TOIE2);

    /* Configure timer2 in normal mode (pure counting, no PWM etc.) */
    TCCR2A &= ~((1<<WGM21) | (1<<WGM20));
    TCCR2B &= ~(1<<WGM22);

    /* Select clock source: internal I/O clock */
    ASSR &= ~(1<<AS2);

    /* Disable Compare Match A interrupt enable (only want overflow) */
    TIMSK2 &= ~(1<<OCIE2A);

    /* Now configure the prescaler to CPU clock divided by 128 */
    TCCR2B |= (1<<CS22)  | (1<<CS20); // Set bits
    TCCR2B &= ~(1<<CS21);             // Clear bit

    /* We need to calculate a proper value to load the timer counter.
    * The following loads the value 131 into the Timer 2 counter register
    * The math behind this is:
    * (CPU frequency) / (prescaler value) = 62500 Hz = 16us.
    * (desired period) / 8us = 208.
    * MAX(uint8) + 1 - 208 = 45;
    */
    /* Save value globally for later reload in ISR */
    tcnt2 = 45; // Set for 300 baud on a 8MHz clock.

    /* Finally load end enable the timer */
    TCNT2 = tcnt2;
    TIMSK2 |= (1<<TOIE2);
}

// Main RTTY ISR

ISR(TIMER2_OVF_vect) {
  TCNT2 = tcnt2; // Reset timer2 counter.

  if(txLock){ // Don't do anything unless we are transmitting!

      // Pull out current byte
      char current_byte = rttyBuffer[current_tx_byte];

      // Null character? Finish transmitting
      if(current_byte == 0){
         txLock = false;
         return;
      }

      int current_bit = 0;

      if(current_byte_position == 0){ // Start bit
          current_bit = 0;
      }else if(current_byte_position == (ASCII_LENGTH + 1)){ // Stop bit
          current_bit = 1;
      }else{ // Data bit
       current_bit = 1&(current_byte>>(current_byte_position-1));
      }

      // Transmit!
      rtty_txbit(current_bit);

      // Increment all our counters.
      current_byte_position++;

      // Have we finished a byte? (+ stop bit)
      if(current_byte_position==(ASCII_LENGTH + 2)){
          current_tx_byte++;
          current_byte_position = 0;
      }
  }
}

// Transmit a bit as a mark or space
void rtty_txbit (int bit) {
	if (bit) {
		// High - mark
		digitalWrite(PIN_RTTY_SPACE, HIGH);
		digitalWrite(PIN_RTTY_MARK, LOW);
	} else {
		// Low - space
		digitalWrite(PIN_RTTY_MARK, HIGH);
		digitalWrite(PIN_RTTY_SPACE, LOW);
	}
}

unsigned int CRC16Sum(char *string) {
	unsigned int i;
	unsigned int crc;
	crc = 0xFFFF;
	// Calculate the sum, ignore $ sign's
	for (i = 0; i < strlen(string); i++) {
		if (string[i] != '$') crc = _crc_xmodem_update(crc,(uint8_t)string[i]);
	}
	return crc;
}

char outputLine[70];
char outputLine2[70];

void hfradioSend() {
    // Do not send if already transmitting
    if (txLock == true)
        return;

    sprintf(outputLine,"$$SHENKI,INSERT,DATA,HERE");

    // Add on the checksum.
    char txSum[6];
    unsigned int checkSum = CRC16Sum(outputLine);
    sprintf(txSum, "%04X", checkSum);
    // There has to be a better way to do this.
    sprintf(outputLine2,"%s*%s\r\n",outputLine,txSum);

    // Send the string.
    rtty_txstring(outputLine2);

}
