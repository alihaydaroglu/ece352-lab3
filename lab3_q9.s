




/*********************************************************************************
 * Initialize the exception vector table
 ********************************************************************************/
				.section .vectors, "ax"

				B 			_start					// reset vector
				B 			SERVICE_UND				// undefined instruction vector
				B 			SERVICE_SVC				// software interrrupt vector
				B 			SERVICE_ABT_INST		// aborted prefetch vector
				B 			SERVICE_ABT_DATA		// aborted data vector
				.word 	0							// unused vector
				B 			SERVICE_IRQ				// IRQ interrupt vector
				B 			SERVICE_FIQ				// FIQ interrupt vector

/* ********************************************************************************

 ********************************************************************************/

				.text

/*
 * Configure the Generic Interrupt Controller (GIC)
*/
CONFIG_GIC:
				/* configure the FPGA IRQ0 (interval timer) and IRQ8 (JTAG) interrupts */
				/* one byte per interrupt */
	 			LDR		R0, =0xFFFED848		// ICDIPTRn: processor targets register
				LDR		R1, =0x00000001		// set target to cpu0 for INTERVAL_TIMER_IRQ
				STR		R1, [R0]
	 			LDR		R0, =0xFFFED850		// ICDIPTRn: processor targets register
				LDR		R1, =0x00000001		// set target to cpu0 for JTAG_IRQ
				STR		R1, [R0]

				/* one bit per interrupt */
				LDR		R0, =0xFFFED108		// ICDISERn: set enable register
				LDR		R1, =0x00010100		// set interrupt enable mask
				STR		R1, [R0]

				/* configure the GIC CPU interface */
				LDR		R0, =0xFFFEC100	// base address of CPU interface
				/* Set Interrupt Priority Mask Register (ICCPMR) */
				LDR		R1, =0xFFFF 	// 0xFFFF enables interrupts of all priorities levels */
				STR		R1, [R0, #0x04]
				/* Set the enable bit in the CPU Interface Control Register (ICCICR). This bit
				 * allows interrupts to be forwarded to the CPU(s) */
				MOV		R1, #0x1
				STR		R1, [R0, #0x00]

				/* Set the enable bit in the Distributor Control Register (ICDDCR). This bit
				 * allows the distributor to forward interrupts to the CPU interface(s) */
				LDR		R0, =0xFFFED000
				STR		R1, [R0, #0x00]

				BX			LR

/*********************** INTERRUPT HANDLERS ***********************/

/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
				B			SERVICE_UND   /* halt execution */

/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
				B			SERVICE_SVC   /* halt execution */

/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
				B			SERVICE_ABT_DATA   /* halt execution */

/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
				B			SERVICE_ABT_INST   /* halt execution */

/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:
				B			SERVICE_FIQ   /* halt execution */

/*--- IRQ ---------------------------------------------------------------------*/

.equ	INTERVAL_TIMER_IRQ, 			72
.equ	JTAG_IRQ, 						80

SERVICE_IRQ:
				PUSH		{R4-R5}

				/* Read the ICCIAR from the CPU interface */
				LDR		R4, =0xFFFEC100	/* (PERIPH_BASE = 0xFFFEC000) + 0x100 */
				LDR		R5, [R4, #0x0C] 			// read the interrupt ID, ack reg


				/* ECE352 - CHECK AND HANDLE INTERRUPTS HERE */
        CMP R5, #80	//Interrupt ID for JTAG is 80
        BLEQ JTAG_ISR
        CMP R5, #72
        BLEQ TIMER_ISR
UNEXPECTED:			BNE UNEXPECTED		//Do not handle interrupts from other devices



EXIT_IRQ:
				/* Write to the End of Interrupt Register (ICCEOIR) */
				STR		R5, [R4, #0x10]

				POP		{R4-R5}
				SUBS		PC, LR, #4

/*********************** DEVICE INITIALIZATION ***********************/

/* Configure the interval timer to create interrupts at 1-sec intervals */
CONFIG_INTERVAL_TIMER:

				/* ECE352 - CONFIGURE INTERVAL TIMER HERE */

    		LDR		R0, =0xFF202000 	/* base address for the timer */
    		LDR		R1, =0x05F5E100 	/* clock cycles */
    		STR		R1, [R0, #0x8] 	/* store low part (high will be ignored) */
    		LSR 	R1, R1, #16 	/* prepare high part */
    		STR 	R1, [R0, #0xC] 	/* set high part */
    		MOV 	R1, #0x7 	/* start, with continuation & interrupts */
    		STR 	R1, [R0, #0x4] 	/* start the timer */

				BX			LR


/* Configure the JTAG to generate read interrupts */
CONFIG_JTAG:

				/* ECE352 - CONFIGURE JTAG DEVICE HERE */
        ldr r1 =0xFF201000
        ldr r3, [r1, #4]
        orr r3, r3  #1
        str r3, [r1, #4]

				BX			LR

/* Echo Character Back from UART */
JTAG_ISR:
				PUSH		{LR}

        LDR		r1, =0xFF201000

JTAG_READ_POLL:
				LDR 	r3, [r1] 	/* Load from the JTAG */
    		ANDS r2, r3, #0x8000 /* Mask other bits */
    		BEQ	 	JTAG_EXIT	/* If this is 0, data is not valid */
    		and r2, r3, #0x00FF /* Data read is now in r2 */

        cmp r2, #72 /* if received 'r' in ASCII */
        mov r7, #1 /* r7 is our global for now */

        cmp r2, #73 /* if received 's' in ASCII */
        mov r7, #0 /* r7 is the global */

JTAG_EXIT:
    		POP		{LR}
    		MOV		PC, LR

/* Timer ISR */

TIMER_ISR:
				PUSH		{LR}
                		LDR		r1, =0xFF201000

JTAG_WRITE_POLL:
				LDR 	r3, [r1, #4] 	/* Load from the JTAG */
    		LSRS 	r3, r3, #16 	/* Check only the write available bits */
    		BEQ	 	JTAG_WRITE_POLL 	/* If this is 0, data cannot be sent yet */

        cmp r7, #0 /* we want speed */
        B SEND_SPEED
        cmp r7, #1
        B SEND_SENSORS
        B EXIT_TIMER_ISR

SEND_SPEED:
        mov r2, #0
        and r2, r8, #0xFF /*r8 is the raw sensor data. anding with FF gives speed*/
        STR 	r2, [r1] 	/* Echo the data back to the JTAG */
        B EXIT_TIMER_ISR
B SEND_SENSORS
        mov r2, #0
        lsr r2, r8, #8 /*r8 is raw data, shift by 8 gives sensors */
        and r2, #0x1F
        STR 	r2, [r1] 	/* Echo the data back to the JTAG */
        B EXIT_TIMER_ISR

EXIT_TIMER_ISR:
      POP		{LR}
      MOV		PC, LR


.equ JTAG_UART, 0xFF211020
.equ LOWER_HWORD_MSK, 0x0000FFFF
.equ TARGET_SPEED, 0x50


/*********************** MAIN PROGRAM ***********************/

				.global	_start
_start:
				/* Set up stack pointers for IRQ and SVC processor modes */
				MOV		R1, #0b11000000 | 0b10010
				MSR		CPSR_c, R1					// change to IRQ mode
				LDR		SP, =0xFFFFFFFF - 3	// set IRQ stack to top of A9 onchip memory
				/* Change to SVC (supervisor) mode with interrupts disabled */
				MOV		R1, #0b11000000 | 0b10011
				MSR		CPSR_c, R1					// change to supervisor mode
				LDR		SP, =0x3FFFFFFF - 3			// set SVC stack to top of DDR3 memory

				BL			CONFIG_GIC					// configure the ARM generic interrupt controller
				BL			CONFIG_INTERVAL_TIMER	// configure the interval timer
				BL			CONFIG_JTAG					// configure the pushbutton KEYs

				/* enable IRQ interrupts in the processor */
				MOV		R1, #0b01000000 | 0b10011		// IRQ unmasked, MODE = SVC
				MSR		CPSR_c, R1


				/* ECE352 - MAIN PROGRAM */

CONTROL_LOOP:
  BL READ_SENSORS
  mov r4, r0
  mov r8, r0
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
