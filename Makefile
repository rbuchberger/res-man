DESTDIR = /usr

.PHONY: install uninstall

install:
	install -D -m 755 res-man $(DESTDIR)/bin/res-man;

uninstall:
	rm -f $(DESTDIR)/bin/res-man;
