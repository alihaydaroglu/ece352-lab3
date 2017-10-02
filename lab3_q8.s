

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
UNEXPECTED:			BNE UNEXPECTED		//Do not handle interrupts from other devices
				BL JTAG_ISR


EXIT_IRQ:
				/* Write to the End of Interrupt Register (ICCEOIR) */
				STR		R5, [R4, #0x10]

				POP		{R4-R5}
				SUBS		PC, LR, #4

/*********************** DEVICE INITIALIZATION ***********************/

/* Configure the interval timer to create interrupts at 1-sec intervals */
CONFIG_INTERVAL_TIMER:

				/* ECE352 - CONFIGURE INTERVAL TIMER HERE */
        BX LR


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
    		BEQ	 	JTAG_READ_POLL 	/* If this is 0, data is not valid */
    		and r2, r3, #0x00FF /* Data read is now in r2 */
JTAG_WRITE:
        LDR r3, [r1, #4] /*Load from JTAG */
        lsrs r3, r3, #16 /*write available bits*/
        beq JTAG_WRITE /*data cannot be sent if 0 */
        str r2, [r1] /*send data back to JTAG */

    		POP		{LR}
    		MOV		PC, LR

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
LOOP:				B LOOP		// Does nothing
