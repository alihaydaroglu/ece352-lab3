.global start

.equ JTAG_UART, 0xFF211020
.equ LOWER_HWORD_MSK, 0x0000FFFF
.equ TARGET_SPEED, 0x50



CONTROL_LOOP:
  BL READ_SENSORS
  mov r4, r0
  /* r4: raw sensor reading */
SPEED:
  /* r1: current speed
     r2: target speed
     r3: acceleration */
  ldr r2, =TARGET_SPEED
  and r1, r4, #0xFF //get speed from raw sensor reading
  cmp r2, r1        //compare current to target speed
  moveq r3, #0      //good speed
  movlt r3, #50     //too slow
  mvngt r3, #50    //too fast
  bl SET_ACC

DECIDE_STEER:
  /* r1: all sensors
     r2: specific sensor
     r3: steer amount */
  lsr r1, r4, #8
  
  /* inner left sensor is 0 - steer right */
  orr r2, r1, #0xFD
  cmp r2, 0xFF
  movne r3, #80
  bne DO_STEER
  
  
	/* inner right sensor is 0 - steer left */
  orr r2, r1, #0xF7
  cmp r2, 0xFF
  mvnne r3, #80
  bne DO_STEER

/* outer left sensor is 0 - steer right */
  orr r2, r1, #0xFE
  cmp r2, 0xFF
  movne r3, #30
  bne DO_STEER

/* outer right sensor is 0 - steer left */
  orr r2, r1, #0xEF
  cmp r2, 0xFF
  mvnne r3, #30
  bne DO_STEER
  
  
  mov r3, #0
  b DO_STEER

DO_STEER:
  mov r0, r3
  BL STEER

B CONTROL_LOOP





/* READ_SENSORS
Requests sensor and speed data, returns values in r0. Loops while incorrect data
is received
  r0: message ID that requests sensor data (0x02)
  r2: we want to check the received packet type, should be 0
*/
READ_SENSORS:
  push {r1-r4, lr}
  mov r0, #0x02
  mov r4, #0
  bl UART_TX        //request sensors

  bl UART_WAIT_RX   //read first byte
  mov r2, #0x00FF0000
  ands r1, r0, r2   //compare first byte to FF
  beq READ_SENSORS  //if first byte is not 0, request sensor data again

  bl UART_WAIT_RX   //shift sensor data to save in r4
  lsl r4, r0, #8

  bl UART_WAIT_RX   //save this stuff in r4
  orr r4, r4, r0

  mov r0, r4        //put the contents of r4 in the return register

  pop {r1-r4, lr}
  mov pc, lr

/* STEER
Steers to value in r0 (-127 to 127)
*/
STEER:
  push {r1}
  mov r1, r0
  mov r0, #0x05
  BL UART_TX
  mov r0, r1
  BL UART_TX
  pop {r1}
  mov pc, lr

/* SET_ACC
Sets acceleration to value in r0
*/
SET_ACC:
  push {r1}
  mov r1, r0
  mov r0, #0x04
  BL UART_TX
  mov r0, r1
  BL UART_TX
  pop {r1}
  mov pc, lr

/* UART_TX Subroutine
Takes the data in R0 and transmits over UART_TX
  r0: byte to be sent, located in the lowest byte of the register
  r1: address of the UART device
  r2: contents of UART control register
  r3: mask to look at only top 4 bits of control register
*/
UART_TX:
  push {r1-r4}
  ldr r1, =JTAG_UART
  ldr r2, [r1, #8]
  ldr r3, =LOWER_HWORD_MSK
  ands r2, r2, r3
  beq UART_TX  //wait if it didn't work
  str r0, [r1]
  pop {r1-r4}
  mov pc, lr

/* UART_WAIT_RX Subroutine
Waits for UART message and returns it in r0
  r0: message to be returned
  r1: address of the UART device
  r2: contents of the data register (bit 15 is the check bit)
*/
UART_WAIT_RX:
  push {r1-r4}
  ldr r1, =JTAG_UART
  ldr r2, [r1]
  ands r3, r2, #8000
  beq UART_WAIT_RX //wait if there is not message yet
  and r0, r2, #0xFF
  pop {r1-r4}

