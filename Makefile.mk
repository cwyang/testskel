# -*- Mode: makefile-gmake -*-
# 2 July 2023
# Chul-Woong Yang

export PROGNAME = dummy.sh
export PERL5LIB = /home/cwyang/perl5/lib/perl5

.NOTPARALLEL:
.PHONY : check_precondition check

all: check_precondition

check_precondition:
	@perl -MNet::EmptyPort -MPath::Tiny -MScope::Guard -MStarlet -MNet::DNS::Nameserver /dev/null > /dev/null 2>&1 || \
	(echo; \
	 echo "Please install following Perl modules: Net::EmptyPort Net::DNS::Nameserver Path::Tiny Scope::Guard Starlet"; \
	 echo && exit 1)
	@which plackup socat curl > /dev/null 2>&1 || \
	(echo; \
	 echo "Please install following programs: plackup socat curl"; \
	 echo && exit 1)

install_pm:
	cpanm install Net::EmptyPort Path::Tiny Scope::Guard Starlet Net::DNS::Nameserver

check:
	sudo t/gen-environ.sh
	sudo -E ip netns exec client bash -c "PERL5LIB=${PERL5LIB} time t/run-tests t/*.t"

