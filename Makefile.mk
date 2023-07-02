# -*- Mode: makefile-gmake -*-
# 2 July 2023
# Chul-Woong Yang

PROGNAME=dummy.sh

.NOTPARALLEL:
.PHONY : check_precondition check

all: check_precondition

check_precondition:
	@perl -MNet::EmptyPort -MPath::Tiny -MScope::Guard -MStarlet -M::Net::DNS::Nameserver /dev/null > /dev/null 2>&1 || \
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
	PROGNAME=${PROGNAME} time t/run-tests t/*.t

