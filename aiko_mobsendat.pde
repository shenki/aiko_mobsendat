/* aiko_modsendat.pde
 * ~~~~~~~~~~~~~~~~~~
 * Please do not remove the following notices.
 * License: GPLv3. http://geekscape.org/static/arduino_license.html
 * Version: 0.0
 * Documentation:  http://geekscape.github.com/aiko_mobsendat
 * Documentation:  http://groups.google.com/group/aiko-platform
 * Documentation:  https://github.com/lukeweston/RocketInstrumentation
 * Documentation:  http://www.freetronics.com/products/mobsendat
 * ----------------------------------------------------------------------------
 *
 * Third-Party libraries
 * ~~~~~~~~~~~~~~~~~~~~~
 * These libraries are not included in the Arduino IDE and
 * need to be downloaded and installed separately.
 *
 * - Aiko framework
 *   https://github.com/geekscape/Aiko
 *
 * - NewSoftSerial library (download is at the bottom of the web page)
 *   http://arduiniana.org/libraries/newsoftserial
 *
 * - PString library
 *   http://arduiniana.org/libraries/pstring
 *
 * - SDFat library
 *   URL ?
 *
 * - SPI library (3rd party "Spi", not Arduino bundled "SPI" library)
 *   URL ?
 *
 * To Do
 * ~~~~~
 * - Check license status of all test code.
 * - Measure cost of each sensor sample and aggregate total time.  Is it okay ?
 * - #define for feature enable / disable.
 * - Separate configuration include file.
 * - Support hardware UART serial output for diagnosis without ZigBee and GPS.
 * - Logging to micro-SD storage.
 * - One-wire temperature sensor.
 * - GPS latitude, longitude, altitude, speed.
 * - 3-axis accelerometer (SPI).
 * - Real Time Clock (write record to storage).
 * - State machine track rocket through ready/boost/flight/recovery/landed.
 *
 * Notes
 * ~~~~~
 * - Millisecond counter cycles after 9 hours, 6 minutes and 7 seconds.
 * - Records format ...
 *   - a:x1,y1,z1,x2,y2,z2,...  # accelerometer x, y, z-axis (m*m/s)
 *   - b:voltage                # battery voltage (volt)
 *   - d:yyyy-mm-dd hh:mm:ss    # real time clock date/time
 *   - e:message                # error message
 *   - g:latitude,longitude,altitude,speed,course,fix,age,date,time
 *                              # gps message
 *   - i:message                # informational message
 *   - p:pressure,temperature   # barometer pressure (pascals), temperature (celcius)
 *   - r:seconds.milliseconds   # run-time since boot
 *   - t:temperature            # one-wire temperature (celcius)
 */

#include <PString.h>
#include <SdFat.h>
#include <Spi.h>
#include "Wire.h"

#include <AikoEvents.h>

#include "aiko_mobsendat.h"

using namespace Aiko;

char globalBuffer[GLOBAL_BUFFER_SIZE];  // Store dynamically constructed string
PString globalString(globalBuffer, sizeof(globalBuffer));

// Accelerometer shared state
byte accelBuffer[40][6];
byte accelSamples;

void setup() {
  serialInitialize();
  accelInitalize();
  storageInitialize();
  barometricInitialize();
  hfradioInitialize();

  Events.addHandler(heartbeatHandler,    HEARTBEAT_PERIOD);
  Events.addHandler(millisecondHandler,                 1);
  Events.addHandler(barometricHandler,                100);
  Events.addHandler(batteryHandler,                  1000);
  Events.addHandler(accelHandler,                     100);
  Events.addHandler(accelDump,                       1000);

  Events.addHandler(hfradioSend,                     5000);
}

void loop() {
  Events.loop();
}

/* ------------------------------------------------------------------------- */

#include <NewSoftSerial.h>

#define DEFAULT_BAUD_RATE  38400

#define SERIAL_BUFFER_SIZE 128

byte serialInitialized = false;

NewSoftSerial serial = NewSoftSerial(PIN_SERIAL_RX, PIN_SERIAL_TX);

void serialInitialize(void) {
  serial.begin(DEFAULT_BAUD_RATE);
  serialInitialized = true;
}

void sendMessage(
  const char* message) {

  serial.println(message);
}

/* ------------------------------------------------------------------------- */

int millisecondCounter = 0;
int secondCounter = 0;

void millisecondHandler(void) {
  if ((++ millisecondCounter) == 1000) {
    millisecondCounter = 0;

    ++ secondCounter;
  }
}

void heartbeatHandler(void) {
  sendMessage(millisecondCounterAsString());

  if (serial.available() > 0) {
    int ch = serial.read();

    if (ch == 'r')  {
      resetCounter();
      sendMessage("reset");
    }
  }
}

const char *millisecondCounterAsString() {
  globalString.begin();
  globalString  = "t:";
  globalString += secondCounter;
  globalString += ".";
  if (millisecondCounter < 10)  globalString += "0";
  if (millisecondCounter < 100) globalString += "0";
  globalString += millisecondCounter;
  return(globalString);
}

void resetCounter(void) {
  secondCounter = millisecondCounter = 0;
}

/* ------------------------------------------------------------------------- */
