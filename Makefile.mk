# -*- Mode: makefile-gmake -*-
# 2 July 2023
# Chul-Woong Yang

VPP_PATH=/home/vagrant/vpp-dev/build-root/install-vpp_debug-native/vpp/bin
export VPP = ${VPP_PATH}/vpp
export VPPCTL = ${VPP_PATH}/vppctl
export PROGS = ${VPP} ${VPPCTL}
export PERL5LIB = $(shell realpath ~/perl5/lib/perl5)

.NOTPARALLEL:
.PHONY : check_precondition check

all: check_precondition

check_precondition:
	@perl -MNet::EmptyPort -MPath::Tiny -MScope::Guard -MStarlet -MNet::DNS::Nameserver /dev/null > /dev/null 2>&1 || \
	(echo; \
	 echo "Please install following Perl modules: Net::EmptyPort Net::DNS::Nameserver Path::Tiny IO::Socket::SSL Scope::Guard Starlet"; \
	 echo && exit 1)
	@which plackup socat curl > /dev/null 2>&1 || \
	(echo; \
	 echo "Please install following programs: plackup socat curl"; \
	 echo && exit 1)

install_pm:
	sudo apt-get install cpanminus
	cpanm install Net::EmptyPort Path::Tiny Scope::Guard Starlet Net::DNS::Nameserver IO::Socket::SSL

check:
	sudo t/gen-environ.sh
	echo ${VPP} ${VPPCTL}
	echo ${ARGS}
#	sudo -E ip netns exec client bash -c "PERL5LIB=${PERL5LIB} time t/run-tests t/*.t"
#	sudo -E ip netns exec client bash -c "PERL5LIB=${PERL5LIB} time t/run-tests t/10env.t"	
	sudo -E ip netns exec client bash -c "PERL5LIB=${PERL5LIB} time t/run-tests t/50_1_base.t"	
