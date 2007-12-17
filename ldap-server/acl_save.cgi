#!/usr/local/bin/perl
# Create, update or delete one access control rule

require './ldap-server-lib.pl';
&error_setup($text{'eacl_err'});
&local_ldap_server() == 1 || &error($text{'slapd_elocal'});
$access{'acl'} || &error($text{'acl_ecannot'});
&ReadParse();

# Get the current rule
&lock_file($config{'config_file'});
$conf = &get_config();
@access = &find("access", $conf);
if (!$in{'new'}) {
	$acl = $access[$in{'idx'}];
	$p = &parse_ldap_access($acl);
	}

if ($in{'delete'}) {
	# Just take out of access list
	@access = grep { $_ ne $acl } @access;
	}
else {
	# Validate and store inputs, starting with object
	if ($in{'what'} == 1) {
		$p->{'what'} = '*';
		}
	else {
		$in{'what_dn'} =~ /^\S+=\S+$/ || &error($text{'eacl_edn'});
		$p->{'what'} =
			'dn'.($in{'what_style'} ? '.'.$in{'what_style'} : '').
			'='.$in{'what_dn'};
		}

	# Object filter and attribute list
	delete($p->{'filter'});
	if ($in{'filter_on'}) {
		$in{'filter'} =~ /^\S+$/ || &error($text{'eacl_efilter'});
		$p->{'filter'} = $in{'filter'};
		}
	delete($p->{'attrs'});
	if ($in{'attrs_on'}) {
		$in{'attrs'} =~ /^\S+$/ || &error($text{'eacl_eattrs'});
		$p->{'attrs'} = $in{'attrs'};
		}

	# Each granted user
	@by = ( );
	for($i=0; defined($in{"wmode_$i"}); $i++) {
		next if ($in{"wmode_$i"} eq "");
		local $by = { };

		# Who are we granting
		if ($in{"wmode_$i"} eq "other") {
			# Other DN
			$in{"who_$i"} =~ /^\S+=\S+$/ ||
				&error(&text('eacl_ewho', $i+1));
			$by->{'who'} = $in{"who_$i"};
			}
		else {
			# Just selected
			$by->{'who'} = $in{"wmode_$i"};
			}

		# Access level
		$in{"access_$i"} =~ /^\S+$/ ||
			&error(&text('eacl_eaccess', $i+1));
		$by->{'access'} = $in{"access_$i"};

		# Additional attributes
		$by->{'control'} = [ &split_quoted_string($in{"control_$i"}) ];
		push(@by, $by);
		}
	$p->{'by'} = \@by;
	# XXX

	# Add to access directive list
	if ($in{'new'}) {
		$acl = { 'name' => 'access',
			 'values' => [ ] };
		push(@access, $acl);
		}
	&store_ldap_access($acl, $p);
	}

# Write out access directives
&save_directive($conf, "access", @access);
&flush_file_lines($config{'config_file'});
&unlock_file($config{'config_file'});

# Log and return
&webmin_log($in{'delete'} ? "delete" : $in{'new'} ? "create" : "modify",
	    "access", $p->{'who'});
&redirect("edit_acl.cgi");

