DESTDIR = /usr

.PHONY: install uninstall

install:
	install -D -m 755 res-man $(DESTDIR)/bin/res-man;
	install -D -m 755 templates/exclude $(DESTDIR)/share/res-man/exclude;
	install -D -m 755 templates/include $(DESTDIR)/share/res-man/include;
	install -D -m 755 templates/myjob $(DESTDIR)/share/res-man/myjob;

uninstall:
	rm -f $(DESTDIR)/bin/res-man;
	rm -rf $(DESTDIR)/share/res-man;
