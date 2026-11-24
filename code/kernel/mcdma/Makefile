#
# Altera MCDMA kernel drivers
#

SUBDIRS := mcdma_kmod

all clean install:
	@for d in $(SUBDIRS); do $(MAKE) -C $$d $@ || exit 1; done

.PHONY: all clean install
