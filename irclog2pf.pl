#!/usr/bin/perl
# Copyright (c) 2006 Svante J. Kvarnstrom <sjk@ankeborg.nu>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

###############################################################################
# Initial setup
#
# This script has been tested with pf on OpenBSD 3.9-stable but will most 
# probably work on other operating systems with (recent versions of) pf 
# installed.
#
# You'll need a pf table dedicated for this. I chose to call mine "drones", but 
# you may of course call it whatever you want (if you do decide to call it 
# something else, please change the constant PFTABLE below.) This is the line
# I use:
#
# table <drones>
#
# in my /etc/pf.conf. Now we can add ip addresses to this table, and we can 
# also have pf act on packets coming in from the ips in the table. I usually
# want to drop packets from known dronehosts, so I use this line:
#
# block drop in log quick on $ext_if from <drones> to ($ext_if) label drones
# 
# One can use the expiretable utility (http://expiretable.fnord.se) to remove
# entries from a pf table based on their age. I call expiretable every hour, 
# using cron, like this:
#
# @hourly		/usr/local/sbin/expiretable -a drones -t 7days
#
# Which means that any drone ips that have been banned for over 7 days will be
# unbanned.
#
# UPDATE 2009-10-25: expiretable is superfluous nowadays since pfctl supports
# the -T expire directive. 

###############################################################################
# Usage - killdrone [-v]
#
# The script parses IRC logs from standard input. Run the script, paste IRC 
# logs and press CTRL+d when done.
#
# The -v switch turns on "verbose" mode. 

# Thanks goes to xkr47 for advice!

use strict;
use warnings;
use Socket;
use Net::hostent;
use Getopt::Std;

use constant VERSION => "0.3.1";
use constant PFTABLE => "drones";

sub main {
	my %hosts;
	my $host;
	my $ip;
	
	my $optptr = process_args();
	
	print "killdrone v".VERSION."\n";

	print "Verbose mode enabled\n" if $optptr->{"v"};

	foreach(<STDIN>) {
		if ($_ =~ /\b~?[a-zA-z0-9._-]{1,10}@([a-zA-Z0-9_.-]+)\b/) {
			$host = $1;
			if ($host =~ /[a-zA-Z]/) { # This is not an ip address
				my $h = gethostbyname($host);
				$h ? $host = inet_ntoa($h->addr) : next; # If $h's null the host couldn't resolve.
			} 
			
			if (defined($hosts{$host})) {
				next; 
			}
			
			$hosts{$host} = 1;
		}
	}

	%hosts = list_ips(%hosts);

	print "\033[2J\033[H";	
	print "\nHosts to block:\n";

	foreach my $ip (sort(keys %hosts)) {
		print "$ip\n";
	}

	my $answer = askq("\nI'm about to block the above ip addresses. Should I proceed? ");
	return if ($answer !~ /y/i);
	
	my $cmd = "pfctl -t ".PFTABLE." -T add ";
	foreach my $ip (sort(keys %hosts)) {
		$cmd .= $ip." ";
	}
	
	print "$cmd\n" if $optptr->{"v"};
	system($cmd);

	$answer = askq("\nDo you also want me to kill the states of these connections? " );

	print "\n";

	if ($answer =~ /y/i) {
		foreach my $ip (sort(keys %hosts)) {
			print "pfctl -k $ip\n" if $optptr->{"v"};
			system("pfctl -k $ip");
		}
	}
}

sub process_args {
    my %opt;
    getopts('v', \%opt);
    return \%opt;
}

sub list_ips {
	my %hosts = (@_);
	
	my $idx = 0;
	my @answers;
	my $answer = 0;

	for (;;) {
		print "\033[2J\033[H";
		print "\n------------------\n";

		foreach my $ip (sort keys %hosts) {
			print ++$idx, " ", $ip, "\n";
		}

		$idx = 0;

		print "--------//--------\n\n";

	    $answer = askq("Ip(s) to ignore (or done): ");
		
		last if ($answer =~ /done/i);

		my @deleteips;
		foreach my $ans (split(/\s*/, $answer)) {
			if ($ans >= 1) {
				push @deleteips, (sort(keys %hosts))[$ans-1]; 
			} else {
				print "Not a valid number\n";
			}
		}	

		foreach my $delip (@deleteips) {
			delete $hosts{$delip};
		}

	}

	return %hosts;
}

sub askq {
	my $question = join('/\s*/', @_);
	print "$question";
	my $answer = <STDIN>;
	chomp $answer;
	return $answer;
}

main();
