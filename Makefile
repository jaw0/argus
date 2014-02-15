# Copyright (c) 2004 by Jeff Weisberg
# Author: Jeff Weisberg <argus @ tcp4me.com>
# Created: 2004-Apr-29
# Function: Developer Makefile
#
# $Id: Makefile,v 1.54 2011/11/03 04:04:23 jaw Exp $


#### Start of configure section

PERL = /usr/local/bin/perl
SENDMAIL = /usr/sbin/sendmail
QPAGE = /usr/local/bin/qpage
FPING = /usr/pkg/sbin/fping
FPING6 = /usr/pkg/sbin/fping6
AUTH_FILE=web_auth_file.pl
DATABASE = DB_File
HAVE_GD = 1
UPGRADING=3.4

INSTALL_LIB  = /home/athena/jaw/projects/argus/bin
INSTALL_SBIN = /home/athena/jaw/projects/argus/bin
INSTALL_BIN  = /home/athena/jaw/projects/argus/bin
INSTALL_CGI  = /home/athena/jaw/projects/argus/bin
INSTALL_DATA = /home/athena/jaw/projects/argus/Data
INSTALL_WWW  = /tmp

#### End of configure section


# import standard makefile
.include "Makefile.tplt"

# experimental code
LIBS_X = Diag.pm


REMOVEAUTH=

all: built/rtc
built/rtc: $(TOOLS) src/rtc.pl
	$(FIXUP) src/rtc.pl > built/rtc
	chmod a+x built/rtc

install-prog: install-rtc
install-rtc:
	cp built/rtc   $(INSTALL_SBIN)/

HTML/faq.html: HTML/FAQ tools/mkfaq
	tools/mkfaq HTML/FAQ > HTML/faq.html
	chmod a+x HTML/faq.html

INSTALL: HTML/install.html
	w3m -dump -O US-ASCII HTML/install.html > INSTALL

dist: INSTALL HTML/config-details.html HTML/debug-details.html HTML/config-since36.html HTML/faq.html
	cd ..; \
	ln -s argus argus-$(VERSION); \
	tar cvXfhz argus/XCLUDE argus-$(VERSION).tgz argus-$(VERSION)/; \
	rm argus-$(VERSION)

darpball:
	cd ..; \
	ln -s argus argus-darp-$(VERSION); \
	tar cvfhz argus-darp-$(VERSION).tgz \
		argus-darp-$(VERSION)/README.DARP argus-darp-$(VERSION)/LICENSE.DARP \
		argus-darp-$(VERSION)/src/DARP*; \
	rm argus-darp-$(VERSION)

plist:
	@echo '@comment $$NetBSD$$'
	@for x in conf.pl $(LIBS) $(TEXT); do echo lib/argus/$$x; done
	@for x in etc/rc.d/rc.argusd sbin/argusd sbin/argusctl sbin/arguscgi \
		lib/argus/graphd lib/argus/picasso bin/argus-config; \
		do echo $$x; done
	@echo @dirrm lib/argus

wtest:
	$${PERLNAME:-perl} -Isrc -MTest::Harness -e 'runtests @ARGV' t/*.t

test:
	$${PERLNAME:-perl} -Isrc -MTest::Harness -e '$$Test::Harness::switches = ""; runtests @ARGV' t/*.t

test-dist:
	mkdir /tmp/test-dist
	tar xCzf /tmp/test-dist ../argus-$(VERSION).tgz
	cd /tmp/test-dist/argus-$(VERSION) ; \
	./Configure --bin /tmp/test-dist/bin --sbin /tmp/test-dist/sbin \
		--lib /tmp/test-dist/lib --data /tmp/test-dist/data --cgi /tmp/test-dist/cgi ; \
	make ; make install
	@cd /tmp/test-dist ; \
	mv data/config.example data/config ; \
	sbin/argusd -t && rm -rf /tmp/test-dist && echo ==== $(PERLNAME) TEST PASSED ====

PERLVERS=perl5.00503 perl5.6.1 perl5.6.2 perl5.8.0 perl5.8.2 perl5.8.4 perl5.8.8 perl5.10.1 perl5.12.4
test-all:
	for x in $(PERLVERS) ; do \
		echo $$x ; \
		make test PERLNAME=$$x ; \
	done

test-dist-all:
	for x in $(PERLVERS) ; do \
		make test-dist PERLNAME=$$x ; \
	done

# -f -nFOO
CI = echo . | ci -l -q -m'periodic'
rcs:
	cvs commit

#	 for x in src/*.* src/cgi src/argusctl src/argus-config src/vxml HTML/*html \
#		 tools/mkfaq tools/fixup tools/install_lib README Makefile \
#		 Makefile.tplt SECURITY THANKSTO LICENSE CHANGES LOCATION \
#		 NOTE HARP TODO UPGRADING Configure misc/* ; \
#		 do test ! -h $$x && ( $(CI) $$x ); done

www-docs:
	scp CHANGES HTML/*html HTML/*css HTML/*gif laertes:/home/argus/html

www-shots:
	scp HTML/shots/*png HTML/shots/*gif laertes:/home/argus/html/shots

www-code:
	scp ../argus-$(VERSION).tgz laertes:~www/htdocs/code/argus-archive/
	scp CHANGES HTML/download.html laertes:/home/argus/html


grapherror:
	-bin/picasso -filetype gif -errortitle 'ARGUS CGI: GRAPH ERROR' -error 'cannot generate graph.   picasso failed.          see web server error log.' > misc/grapherror.gif

