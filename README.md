= Elfos-jiffy

This is a loadable module for Elf/OS that implements an interrupt-driven software clock using the internal timer on an 1804/5/6 processor. Because it's interrupt-driven and keeps time right in the kernel memory, this is a "magic" clock that doesn't need any BIOS or other interface. The time in memory that the kernel references is just always up-to-date.

Obviously this clock needs to be set whenever it is loaded, this can be done with the standard Elf/OS date command, at least when using the current version from Github at (rileym65/Elf/Elfos-date)[https://github.com/rileym65/Elf-Elfos-date].

For now, this is hard-coded for a 4 Mhz processor clock, but can theoretically work on any clock rate and in the future I'll make it configurable at run time. With the 4 Mhz clock, the interrupt rate is approximately 61.035 hertz (actually exactly 15625/256 hertz). The clock is as accurate as your oscillator.

Note that this will cause massive input and output errors on the console when using a software UART. Not recommended.

