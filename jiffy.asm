; You have permission to use, modify, copy, and distribute
; this software so long as this copyright notice is retained.
; This software may not be used in commercial applications
; without express written permission from the author.


           ; Include kernal API entry points

           include bios.inc
           include kernel.inc

           ; Define non-published API elements

intret     equ     03f0h
iserve     equ     03f6h
ivec       equ     03fdh
himem      equ     0442h
date_time  equ     0475h

           ; Executable program header

           org     2000h - 6
           dw      start
           dw      end-start
           dw      start

start:     org     2000h
           br      main

           ; Build information

           db      7+80h              ; month
           db      18                 ; day
           dw      2021               ; year
           dw      1                  ; build
           db      'Written by David S. Madole',0

           ; Since this requires the timer that in unique to the 1804/5/6
           ; processors, check that we are running on one of those first.
           ;
           ; On an 1804/5/6 the RLDI RB (68 CB XX XX) instruction below will
           ; load the address PROCFAIL into register RB. But an 1802 will see
           ; this as an INP 0 (68) instruction (nearly a no-op) followed by
           ; a LBNF (CB XX XX) instruction branching if DF=0 to PROCFAIL.

main:      adi     0                  ; clear df so 1802 will take lbnf
           rldi    rb,procfail        ;  this is (inp, lbnf) on 1802

           ; Check minimum kernel version we need before doing anything else,
           ; in particular we need support for himem variable to allocate
           ; memory for persistent module to use.

           ldi     high himem         ; get pointer to himem variable
           phi     r7
           ldi     low himem
           plo     r7

           ldn     r7                 ; if high byte is zero, not supported
           lbz     versfail

           ; Allocate memory below himem for the driver code block, leaving
           ; address to copy code into in register R8 and R9 and length
           ; of code to copy in RF. Updates himem to reflect allocation.

allocmem:  ldi     high himem         ; pointer to top of memory variable
           phi     r7
           ldi     low himem
           plo     r7

           inc     r7                 ; move to lsb of himem
           ldn     r7                 ;  subtract size to install from himem
           smi     low end-module-1   ;  keep borrow flag of result
           ldi     0                  ;  but round down to page boundary
           plo     r8
           plo     r9

           dec     r7                 ; move to msb of himem and finish
           ldn     r7                 ;  subtraction to get code block address
           smbi    high end-module-1
           phi     r8
           phi     r9

           dec     r8                 ; set himem to one less than block

           ghi     r8                 ; update himem to below new block
           str     r7
           inc     r7
           glo     r8
           str     r7
           dec     r7

           inc     r8                 ; restore to start of code block


           ; Copy the code of the persistent module to the memory block that
           ; was just allocated. R8 and R9 both point to this block before
           ; the copy. R9 will be used but R8 will still point to it after.

           ldi     high module         ; get source address to copy from
           phi     rd
           ldi     low module
           plo     rd

           ldi     high end-module+255
           phi     rf
           ldi     low end-module+255
           plo     rf

copycode:  lda     rd                 ; copy code to destination address
           str     r9
           inc     r9
           dec     rf
           ghi     rf
           lbnz    copycode

           ; Patch existing interrupt vector into our exit jump, and at the
           ; same time, patch our interrupt service routine into the Elf/OS
           ; interrupt handler chain. Also set R1 to point to the Elf/OS
           ; stub interrupt handler since Elf/OS doesn't.

           ghi     r8                  ; set rd to point to the argument of
           phi     rd                  ;  the lbr instruction in our isr
           ldi     low intretrn+1
           plo     rd

           ldi     high ivec           ; get pointer to elf/os ivec vector
           phi     rf
           ldi     low ivec
           plo     rf

           sex     r3                  ; so argument of dis/ret is inline
           dis                         ;   no interrupts while making changes
           db      23h

           ldn     rf                  ; set msb of existing isr into lbr
           str     rd                  ;  instruction to return from our isr,
           ghi     rd                  ;  and set our isr address into ivec
           str     rf

           inc     rf                  ; advance to lsb of both ivec and our
           inc     rd                  ;  return lbr instruction argument

           ldn     rf                  ; now do the same with lsb of addresses
           str     rd
           ldi     low intenter
           str     rf

           ldi     high iserve         ; elf/os provides an isr stub but
           phi     r1                  ;  does not actually point r1 to it
           ldi     low iserve
           plo     r1

           sex     r3                  ; so argument of dis/ret is inline
           ret                         ;  re-enable interrupts now
           db      23h

           ; Initialize and enable the 1804/5/6 timer as a source of periodic
           ; interrupts. This won't work on an 1802.

           ldi     low 256            ; load timer with 256 (0)
           ldc                        ;  for maximum interval
           stm                        ;  and start timer

           ; We are done and the clock is running, now exit.

           sep     scall
           dw      o_inmsg
           db      '1804/5/6 Clock Driver Build 1 for Elf/OS',13,10,0
           sep     sret

           ; Failure message if not run on an 1804/5/6 processor

procfail:  sep     scall
           dw      o_inmsg
           db      'ERROR: This driver requires an 1804/5/6 CPU',13,10,0
           sep     sret

           ; Failure message if kernel does not support himem

versfail:  sep     scall
           dw      o_inmsg
           db      'ERROR: Needs kernel version 0.3.1 or higher',13,10,0
           sep     sret


           org     $ + 0ffh & 0ff00h

module:    ; Start the actual module code on a new page so that it forms
           ; a block of page-relocatable code that will be copied to himem.

           ; This interrupt service routine is called by the Elf/OS stub
           ; service routine which saves the X, P, D, and DF registers. It
           ; also decrements R2, so it's safe to use the top of the stack.

intcmplt:  sex     r2                  ; the next isr might assume this

           inc     r2                  ; restore saved rd register before
           lda     r2                  ;  jumping to return
           phi     rd
           ldn     r2
           plo     rd

           ; Entry point is here

intenter:  ;db      68h,3eh,gottimer & 0ffh
           bci     gottimer

intretrn:  lbr     intret

           ; This works by counting fractions of seconds, which it actually
           ; counts as fractions so that odd ratios can be accomodated
           ; with just integer math and no rounding errors. Right now this
           ; is hard-coded for the minimum frequency possible from the 
           ; 1804 timer with a 4 Mhz processor clock, which is about 61.035
           ; hertz, or more precisely, the time between interrupts is
           ; 256/15625 of a second, which is what this counts. Later,
           ; I will make this configurable for different clock frequencies
           ; but the math is more complicated than I want to figure out now.

gottimer:  glo     rd                  ; we need a register to do anything
           stxd                        ;  so push rd so we can use it
           ghi     rd
           stxd

           ghi     r1                  ; get pointer to memory variables
           phi     rd                  ;  point to lsb of fraction
           ldi     low fracts+1
           plo     rd

           sex     rd

           ; Count ticks in fractional seconds of time

           ldn     rd                  ; subtract the numerator of the tick
           smi     low 256             ;  length from the time fraction
           stxd

           ldn     rd                  ; continue with the msb
           smbi    high 256 
           str     rd

           bdf     intcmplt            ; exit if result is positive

           inc     rd                  ; move back to lsb

           ldn     rd                  ; add the denominator to the
           adi     low 15625           ;  remaining negative result
           stxd

           ldn     rd                  ; same with the msb
           adci    high 15625
           stxd

           ; Update the real time when the fraction crosses one second

           ldi     high date_time+5    ; point to seconds byte in kernel
           phi     rd
           ldi     low date_time+5
           plo     rd

           ldn     rd                  ; get seconds
           sdi     59                  ;  sutract from last second
           bz      minute              ;  if zero, rolling over

           sdi     60                  ; otherwise subtract from 60
           str     rd                  ;  to increment and update
           br      intcmplt            ;  then return

minute:    stxd                        ; zero seconds, move to minutes

           ldn     rd                  ; get minutes
           sdi     59                  ;  subtract from last minute
           bz      hour                ;  if zero, rolling over

           sdi     60                  ; otherwise subtract from 60
           str     rd                  ;  to increment and update
           br      intcmplt            ;  then return

hour:      stxd                        ; zero minutes, move to hours

           ldn     rd                  ; get hours
           sdi     23                  ;  subtract from last hour
           bz      day                 ;  if zero, rolling over

           sdi     24                  ; otherwise subtract from 24
           str     rd                  ;  to increment and update
           br      intcmplt            ;  then return

day:       stxd                        ; zero hours, move to day
           dec     rd                  ; move to month
           dec     rd

           lda     rd                  ;  get month
           xri     2                   ;  compare to 2
           bz      february            ;  if equal then special case

           smi     8                   ; extend bit 3 into df flag
           adci    0                   ;  add df flag back in
           ani     1                   ;  keep just lowest bit
           adi     30                  ;  add to 30 to get last day
           br      lastday

february:  inc     rd                  ; move to year
           ldn     rd                  ;  get year, move to month
           dec     rd

           ani     3                   ; mask three lowest bits
           sdi     0                   ;  set df if zero
           ldi     0                   ;  clear d
           adci    28                  ;  add to 28 to get last day

lastday:   sm                          ;  subtract from last day
           bz      month               ;  if zero, rolling over

           ldn     rd                  ; get day again,
           adi     1                   ;  add one,
           str     rd                  ;  update,
           br      intcmplt            ;  and return

month:     shlc                        ; get a 1 and store (df was set)
           stxd                        ;  into day, move to month

           ldn     rd                  ; get month
           sdi     12                  ;  subtract from last month
           bz      year                ;  if zero, rolling over

           sdi     13                  ; otherwise add 13 back
           str     rd                  ;  to increment and update
           br      intcmplt            ;  then return

year:      shlc                        ; get a 1 and store (df was set)
           str     rd                  ;  into month, move to year
           inc     rd
           inc     rd

           add                         ; add the 1 to the year
           str     rd                  ;  and store back

           br      intcmplt

fracts:    dw      15625               ; this is where the fraction is kept

end:       ; That's all folks!


