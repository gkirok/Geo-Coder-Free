package Geo::Coder::Free::OpenAddresses;

use strict;
use warnings;

use Geo::Coder::Free::DB::OpenAddr;
use Geo::Coder::Free::DB::openaddresses;
use Module::Info;
use Carp;
use File::Spec;
use File::pfopen;
use Locale::CA;
use Locale::US;
use CHI;
use Locale::Country;

our %admin1cache;
our %admin2cache;

#  Some locations aren't found because of inconsistencies in the way things are stored - these are some values I know
# FIXME: Should be in a configuration file
my %known_locations = (
	'Newport Pagnell, Buckinghamshire, England' => {
		'latitude' => 52.08675,
		'longitude' => -0.72270
	},
);

=head1 NAME

Geo::Coder::Free::OpenAddresses - Provides a geocoding functionality to the data from openaddresses.io

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Geo::Coder::Free::OpenAddresses

    # Use a local download of http://results.openaddresses.io/
    my $geocoder = Geo::Coder::Free::OpenAddresses->new(openaddr => $ENV{'OPENADDR_HOME'});
    $location = $geocoder->geocode(location => '1600 Pennsylvania Avenue NW, Washington DC, USA');

=head1 DESCRIPTION

Geo::Coder::Free::OpenAddresses provides an interface to the free geolocation database at http://openadresses.io

Refer to the source URL for licencing information for these files:
openaddress data can be downloaded from http://results.openaddresses.io/.

To significantly speed this up use the provided createdatabases.PL script which ingests the data into an SQLite database.

=head1 METHODS

=head2 new

    $geocoder = Geo::Coder::Free::OpenAddresses->new();

Takes one parameter, openaddr, which is the base directory of
the OpenAddresses data downloaded from http://results.openaddresses.io.

=cut

sub new {
	my($proto, %param) = @_;
	my $class = ref($proto) || $proto;

	# Geo::Coder::Free->new not Geo::Coder::Free::new
	return unless($class);

	# Geo::Coder::Free::DB::init(directory => 'lib/Geo/Coder/Free/databases');

	my $directory = Module::Info->new_from_loaded(__PACKAGE__)->file();
	$directory =~ s/\.pm$//;

	Geo::Coder::Free::DB::init({
		directory => File::Spec->catfile($directory, 'databases'),
		cache => CHI->new(driver => 'Memory', datastore => { })
	});

	if(my $openaddr = $param{'openaddr'}) {
		Carp::carp "Can't find the directory $openaddr"
			if((!-d $openaddr) || (!-r $openaddr));
		return bless { openaddr => $openaddr}, $class;
	} 
	Carp::croak(__PACKAGE__ . ": usage: new(openaddr => '/path/to/openaddresses')");
}

=head2 geocode

    $location = $geocoder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

    # TODO:
    # @locations = $geocoder->geocode('Portland, USA');
    # diag 'There are Portlands in ', join (', ', map { $_->{'state'} } @locations);

=cut

sub geocode {
	my $self = shift;

	my %param;
	if(ref($_[0]) eq 'HASH') {
		%param = %{$_[0]};
	} elsif(@_ % 2 == 0) {
		%param = @_;
	} else {
		$param{location} = shift;
	}

	my $location = $param{location}
		or Carp::croak("Usage: geocode(location => \$location)");

	if($location =~ /^(.+),\s*Washington\s*DC,(.+)$/) {
		$location = "$1, Washington, DC, $2";
	}

	if($known_locations{$location}) {
		return $known_locations{$location};
	}

	my $county;
	my $state;
	my $country;
	my $country_code;
	my $street;
	my $concatenated_codes;

	# TODO: this is horrible.  Is there an easier way?  Now that MaxMind is handled elsewhere, I hope so
	if($location =~ /^([\w\s\-]+)?,([\w\s]+),([\w\s]+)?$/) {
		# Turn 'Ramsgate, Kent, UK' into 'Ramsgate'
		$location = $1;
		$county = $2;
		$country = $3;
		$location =~ s/\-/ /g;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
		if($location =~ /^St\.? (.+)/) {
			$location = "Saint $1";
		}
		if(($country =~ /^(United States|USA|US)$/)) {
			$state = $county;
			$county = undef;
		}
	} elsif($location =~ /^([\w\s\-]+)?,([\w\s]+),([\w\s]+),\s*(Canada|United States|USA|US)?$/) {
		$location = $1;
		$county = $2;
		$state = $3;
		$country = $4;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$state =~ s/^\s//g;
		$state =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
	} elsif($location =~ /^[\w\s-],[\w\s-]/) {
		Carp::croak(__PACKAGE__, ": can't parse and handle $location");
		return;
	} elsif($location =~ /,\s*([\w\s]+)$/) {
		$country = $1;
		if(defined($country) && (($country eq 'UK') || ($country eq 'United Kingdom') || ($country eq 'England'))) {
			$country = 'Great Britain';
		}
		if(my $c = country2code($country)) {
			my $openaddr_db;
			my $countrydir = File::Spec->catfile($self->{openaddr}, lc($c));
			if((!(-d $countrydir)) || !(-r $countrydir)) {
				# Carp::croak(__PACKAGE__, ": unsupported country $country");
				return;
			}
		} else {
			Carp::croak(__PACKAGE__, ": unknown country $country");
			return;
		}
	} elsif($location =~ /^([\w\s\-]+)?,([\w\s]+),([\w\s]+),([\w\s]+),([\w\s]+)?$/) {
		$street = $1;
		$location = $2;
		$county = $3;
		$state = $4;
		$country = $5;
		$location =~ s/^\s//g;
		$location =~ s/\s$//g;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$state =~ s/^\s//g;
		$state =~ s/\s$//g;
		$street =~ s/^\s//g;
		$street =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
		::diag('11111111111111111');
	} elsif($location =~ /^([\w\s]+),([\w\s]+),([\w\s]+),\s*([\w\s]+)?$/) {
		$location = $1;
		$county = $2;
		$state = $3;
		$country = $4;
		$location =~ s/^\s//g;
		$location =~ s/\s$//g;
		$county =~ s/^\s//g;
		$county =~ s/\s$//g;
		$state =~ s/^\s//g;
		$state =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
	} elsif($location =~ /^([\w\s]+),\s*([\w\s]+)?$/) {
		$location = $1;
		$country = $2;
		$location =~ s/^\s//g;
		$location =~ s/\s$//g;
		$country =~ s/^\s//g;
		$country =~ s/\s$//g;
		if(!country2code($country)) {
			$county = $country;
			$country = undef;
		}
	} else {
		# For example, just a country or state has been given
		Carp::croak(__PACKAGE__, "Can't parse '$location'");
		return;
	}
	return if(!defined($country));	# FIXME: give warning

	my $countrycode = country2code($country);

	return if(!defined($countrycode));	# FIXME: give warning

	$countrycode = lc($countrycode);
	my $openaddr_db;
	my $countrydir = File::Spec->catfile($self->{openaddr}, $countrycode);
	# TODO:  Don't use statewide if the county can be determined, since that file will be much smaller
	if($state && (-d $countrydir)) {
		# TODO:  Locale::CA for Canadian provinces
		if(($state =~ /^(United States|USA|US)$/) && (length($state) > 2)) {
			if(my $twoletterstate = Locale::US->new()->{state2code}{uc($state)}) {
				$state = $twoletterstate;
			}
		} elsif($country =~ /^(United States|USA|US)$/) {
			if(my $twoletterstate = Locale::US->new()->{state2code}{uc($state)}) {
				$state = $twoletterstate;
			}
			my $l = length($state);
			if($l > 2) {
				if(my $twoletterstate = Locale::US->new()->{state2code}{uc($state)}) {
					$state = $twoletterstate;
				}
			} elsif($l == 2) {
				$state = lc($state);
			}
		}
		my $statedir = File::Spec->catfile($countrydir, $state);
		if(-d $statedir) {
			if($countrycode eq 'us') {
				$openaddr_db = $self->{openaddr_db} ||
					Geo::Coder::Free::DB::openaddresses->new(
						directory => $self->{openaddr},
						cache => CHI->new(driver => 'Memory', datastore => { })
					);
				$self->{openaddr_db} = $openaddr_db;
			} else {
				$openaddr_db = $self->{$statedir} || Geo::Coder::Free::DB::OpenAddr->new(directory => $statedir, table => 'statewide');
			}
			if($location) {
				$self->{$statedir} = $openaddr_db;
				my %args = (city => uc($location));
				if($street) {
					$args{'street'} = uc($street);
				}
				if($state) {
					$args{'state'} = uc($state);
				}
				my $rc = $openaddr_db->fetchrow_hashref(%args);
				if($rc && defined($rc->{'lat'})) {
					$rc->{'latitude'} = $rc->{'lat'};
					$rc->{'longitude'} = $rc->{'lon'};
					return $rc;
				}
				if($location =~ /^(\d+)\s+(.+)$/) {
					$rc = $openaddr_db->fetchrow_hashref('number' => $1, 'street' => uc($2), 'city' => uc($county));
				} else {
					$rc = $openaddr_db->fetchrow_hashref('street' => uc($location), 'city' => uc($county));
				}
				if($rc && defined($rc->{'lat'})) {
					$rc->{'latitude'} = $rc->{'lat'};
					$rc->{'longitude'} = $rc->{'lon'};
					return $rc;
				}
			}
			die $statedir;
		}
	} elsif($county && (-d $countrydir)) {
		my $is_state;
		my $table;
		if($country =~ /^(United States|USA|US)$/) {
			my $l = length($county);
			if($l > 2) {
				if(my $twoletterstate = Locale::US->new()->{state2code}{uc($county)}) {
					$county = $twoletterstate;
					$is_state = 1;
					$table = 'statewide';
				}
			} elsif($l == 2) {
				$county = lc($county);
				$is_state = 1;
				$table = 'statewide';
			}
		} elsif($country eq 'Canada') {
			my $l = length($county);
			if($l > 2) {
				if(my $province = Locale::CA->new()->{province2code}{uc($county)}) {
					$county = $province;
					$is_state = 1;
					$table = 'province';
				}
			} elsif($l == 2) {
				$county = lc($county);
				$is_state = 1;
				$table = 'province';
			}
			$table = 'city_of_' . lc($location);
			$location = '';	# Get the first location in the city.  Anyone will do
		}
		my $countydir = File::Spec->catfile($countrydir, lc($county));
		if(-d $countydir) {
			if($table && $is_state) {
				# FIXME:  allow SQLite file
				if(File::pfopen::pfopen($countydir, $table, 'csv:db:csv.db:db.gz:xml:sql')) {
					if($countrycode eq 'us') {
						$openaddr_db = $self->{openaddr_db} ||
							Geo::Coder::Free::DB::openaddresses->new(
								directory => $self->{openaddr},
								cache => CHI->new(driver => 'Memory', datastore => { })
							);
						$self->{openaddr_db} = $openaddr_db;
					} else {
						# FIXME - self->{$countydir} can point to a town in Canada
						$openaddr_db = $self->{$countydir} || Geo::Coder::Free::DB::OpenAddr->new(directory => $countydir, table => $table);
					}
					$self->{$countydir} = $openaddr_db;
					if(defined($location)) {
						if($location eq '') {
							# Get the first location in the city.  Anyone will do
							my $rc = $openaddr_db->execute('SELECT DISTINCT LAT, LON FROM city_of_edmonton WHERE city IS NULL');
							if($rc && defined($rc->{'LAT'})) {
								$rc->{'latitude'} = $rc->{'LAT'};
								$rc->{'longitude'} = $rc->{'LON'};
								return $rc;
							}
						}
						my $rc = $openaddr_db->fetchrow_hashref('city' => uc($location));
						if($rc && defined($rc->{'lat'})) {
							$rc->{'latitude'} = $rc->{'lat'};
							$rc->{'longitude'} = $rc->{'lon'};
							return $rc;
						}
						$openaddr_db = undef;
					} else {
						die;
					}
				}
			} else {
				$openaddr_db = Geo::Coder::Free::DB::OpenAddr->new(directory => $countydir);
				die $countydir;
			}
		}
	} else {
		$openaddr_db = Geo::Coder::Free::DB::OpenAddr->new(directory => $countrydir);
		die $param{location};
	}
	if($openaddr_db) {
		die "TBD";
	}
}

=head2 reverse_geocode

    $location = $geocoder->reverse_geocode(latlng => '37.778907,-122.39732');

To be done.

=cut

sub reverse_geocode {
	Carp::croak('Reverse lookup is not yet supported');
}

=head2	ua

Does nothing, here for compatibility with other geocoders

=cut

sub ua {
}

=head1 AUTHOR

Nigel Horne <njh@bandsman.co.uk>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 BUGS

Lots of lookups fail at the moment.

The openaddresses.io code has yet to be compeleted.
There are die()s where the code path has yet to be written.

The MaxMind data only contains cities.
The openaddresses data doesn't cover the globe.

Can't parse and handle "London, England".

Openaddresses look up is slow.
If you rebuild the csv databases as SQLite it will be much quicker.
This should work, but I haven't tested it yet.

=head1 SEE ALSO

VWF, openaddresses, MaxMind and geonames.

=head1 LICENSE AND COPYRIGHT

Copyright 2017-2018 Nigel Horne.

The program code is released under the following licence: GPL for personal use on a single computer.
All other users (including Commercial, Charity, Educational, Government)
must apply in writing for a licence for use from Nigel Horne at `<njh at nigelhorne.com>`.

This product includes GeoLite2 data created by MaxMind, available from
http://www.maxmind.com

=cut

1;
