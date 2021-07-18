PROJECT = jiffy

$(PROJECT).prg: $(PROJECT).asm bios.inc kernel.inc
	rcasm -l -v -x -d 1805 $(PROJECT) > $(PROJECT).lst
	hextobin $(PROJECT)

clean:
	-rm -f $(PROJECT).prg
	-rm -f $(PROJECT).bin
	-rm -f $(PROJECT).lst

