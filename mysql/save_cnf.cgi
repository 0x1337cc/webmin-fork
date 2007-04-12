#!/usr/local/bin/perl
# Save mysql server configuration options

require './mysql-lib.pl';
$access{'perms'} == 1 || &error($text{'cnf_ecannot'});
&error_setup($text{'cnf_err'});
&ReadParse();

# Get the mysqld section
&lock_file($config{'my_cnf'});
$conf = &get_mysql_config();
($mysqld) = grep { $_->{'name'} eq 'mysqld' } @$conf;
$mysqld || &error($text{'cnf_emysqld'});

# Parse mysql server inputs
if ($in{'port_def'}) {
	&save_directive($conf, $mysqld, "port", [ ]);
	}
else {
	$in{'port'} =~ /^\d+$/ && $in{'port'} > 0 && $in{'port'} < 65536 ||
		&error($text{'cnf_eport'});
	&save_directive($conf, $mysqld, "port", [ $in{'port'} ]);
	}

if ($in{'bind_def'}) {
	&save_directive($conf, $mysqld, "bind-address", [ ]);
	}
else {
	&check_ipaddress($in{'bind'}) ||
		&error($text{'cnf_ebind'});
	&save_directive($conf, $mysqld, "bind-address", [ $in{'bind'} ]);
	}

if ($in{'socket_def'}) {
	&save_directive($conf, $mysqld, "socket", [ ]);
	}
else {
	$in{'socket'} =~ /^\/\S+$/ ||
		&error($text{'cnf_esocket'});
	&save_directive($conf, $mysqld, "socket", [ $in{'socket'} ]);
	}

if ($in{'datadir_def'}) {
	&save_directive($conf, $mysqld, "datadir", [ ]);
	}
else {
	-d $in{'datadir'} || &error($text{'cnf_edatadir'});
	&save_directive($conf, $mysqld, "datadir", [ $in{'datadir'} ]);
	}

&save_directive($conf, $mysqld, "skip-locking",
		$in{'skip-locking'} ? [ "" ] : [ ]);

&save_directive($conf, $mysqld, "big-tables",
		$in{'big-tables'} ? [ "" ] : [ ]);

# Save set variables
%vars = &parse_set_variables(&find_value("set-variable", $mems));
foreach $w (@mysql_set_variables, @mysql_number_variables) {
	if ($in{$w."_def"}) {
		delete($vars{$w});
		}
	else {
		$in{$w} =~ /^\d+$/ || &error($text{"cnf_e".$w});
		$vars{$w} = $in{$w}.$in{$w."_units"};
		}
	}
@sets = ( );
foreach $v (keys %vars) {
	push(@sets, $v."=".$vars{$v});
	}
&save_directive($conf, $mysqld, "set-variable", \@sets);

# Write out file
&flush_file_lines();
&unlock_file($config{'my_cnf'});
&webmin_log("cnf");
&redirect("");

