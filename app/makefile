.PHONY: appdir package_gma package_gmi

SUBDIRS=\
 strings

TOP=..
FGLLDPATH=../common
FGLDBPATH=../common

FORMS=\
  params.42f\
  password.42f\
  contform.42f\
  contnote.42f\
  contlist.42f\
  contmap.42f\
  list1.42f

RESOURCES=\
  contacts.4ad

IMAGES=\
  images/anonymous.jpg

MAIN=\
  main.42m

MODULES=\
  params.42m\
  password.42m\
  contnotes.42m

OTHERS=\
  ../common/libutil.42m\
  ../common/mkcontacts.42m\
  ../common/dbsync_contact.42m

all:: $(FORMS) $(MODULES) $(MAIN)

BUILDDIR=$(TOP)/build
$(BUILDDIR):
	$(MKDIR) $(BUILDDIR)

APPDIR=$(BUILDDIR)/appdir
$(APPDIR): $(BUILDDIR)
	$(MKDIR) $(APPDIR)

appdir:: all $(APPDIR)
	rm -rf $(APPDIR)/*
	$(CP) $(RESOURCES) $(APPDIR)
	$(MKDIR) $(APPDIR)/images
	$(CP) $(IMAGES) $(APPDIR)/images
	$(CP) fglprofile $(APPDIR)
	$(CP) $(MODULES) $(APPDIR)
	$(CP) $(OTHERS) $(APPDIR)
	$(CP) $(FORMS) $(APPDIR)
	$(CP) $(MAIN) $(APPDIR)
	$(CP) strings/en/contacts.42s $(APPDIR)
	$(MKDIR) $(APPDIR)/fr
	$(CP) strings/fr/contacts.42s $(APPDIR)/fr
	$(MKDIR) $(APPDIR)/zh_TW
	$(CP) strings/zh_TW/contacts.42s $(APPDIR)/zh_TW

package_gma:: appdir
	sh build_gma.sh

package_gmi:: appdir
	sh build_gmi.sh

clean::
	rm -rf $(APPDIR)
	rm -rf contacts.log

include ../makefile.incl

