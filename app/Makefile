EXEC = app

all:  $(EXEC)

$(EXEC):  UserApp.c cpPdes.s
	cnycc -g UserApp.c cpPdes.s -o $@

clean:
	rm -f $(EXEC)

