
SUBDIRS=\
 common \
 app \
 server

all:: $(SUBDIRS)

clean::
	rm -rf build

include makefile.incl


