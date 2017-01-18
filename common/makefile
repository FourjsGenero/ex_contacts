MODULES= \
 libutil.42m \
 mkcontacts.42m \
 fill_contacts.42m \
 dbsync_contact.42m

all:: $(MODULES)

database:: all
	$(FGLRUN) mkcontacts_main.42m -d contacts -s
	fgldbsch -db contacts

dbsync_contact.42m:: dbsync_contact.4gl contacts.sch

include ../makefile.incl

