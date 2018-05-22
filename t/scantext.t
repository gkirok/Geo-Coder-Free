#!perl -w

use warnings;
use strict;
use Test::Most tests => 15;
use Test::Number::Delta;
use Test::Carp;
use lib 't/lib';
use MyLogger;

BEGIN {
	use_ok('Geo::Coder::Free');
}

SCANTEXT: {
	SKIP: {
		if($ENV{'OPENADDR_HOME'}) {
			diag('This will take some time and memory');

			Geo::Coder::Free::DB::init(logger => new_ok('MyLogger'));

			my $geocoder = new_ok('Geo::Coder::Free' => [ openaddr => $ENV{'OPENADDR_HOME'} ]);
			my @locations = $geocoder->geocode(scantext => 'I was born in Ramsgate, Kent, England');
			ok(scalar(@locations) == 1);
			my $location = $locations[0];
			delta_within($location->{latitude}, 51.33, 1e-2);
			delta_within($location->{longitude}, 1.41, 1e-2);
				
			@locations = $geocoder->geocode(scantext => "I was born at St Mary's Hospital in Newark, DE in 1987");
			my $found = 0;
			foreach $location(@locations) {
				if($location->{'city'} ne 'NEWARK') {
					next;
				};
				if($location->{'state'} ne 'DE') {
					next;
				};
				if($location->{'country'} ne 'US') {
					next;
				};
				$found++;
				delta_within($location->{latitude}, 39.68, 1e-2);
				delta_within($location->{longitude}, -75.66, 1e-2);

			}
			ok($found == 1);
			my $s = 'From the Indianapolis Star, 25/4/2013:  "75, Indianapolis, died Apr. 21, 2013. Services: 1 p.m. Apr. 26 in Forest Lawn Funeral Home, Greenwood, with visitation from 11 a.m.".  Obituary from Forest Lawn Funeral Home:  "Sharlene C. Cloud, 75, of Indianapolis, passed away April 21, 2013. She was born May 21, 1937 in Noblesville, IN to Virgil and Josephine (Beaver) Day. She is survived by her mother; two sons, Christopher and Thomas Cloud; daughter, Marsha Cloud; three sisters, Mary Kirby, Sharon Lowery, and Doris Lyng; two grandchildren, Allison and Jamie Cloud. Funeral Services will be Friday at 1:00 pm at Forest Lawn Funeral Home, Greenwood, IN, with visitation from 11:00am till time of service Friday at the funeral home."';
			@locations = $geocoder->geocode({ scantext => $s, region => 'US' });
			my %found;
			# diag(Data::Dumper->new([\@locations])->Dump());
			foreach $location(@locations) {
				my $city;
				next if(!defined($city = $location->{'city'}));
				# diag("$city: ", $location->{'confidence'});
				if(defined($location->{'state'}) && $location->{'state'} ne 'IN') {
					next;
				};
				if($location->{'country'} ne 'US') {
					next;
				};
				if($city eq 'GREENWOOD') {
					if(!$found{'GREENWOOD'}) {
						$found{'GREENWOOD'}++;
						delta_within($location->{latitude}, 39.6, 1e-1);
						delta_within($location->{longitude}, -86.1, 1e-1);
					}
				} elsif($city eq 'NOBLESVILLE') {
					if(!$found{'NOBLESVILLE'}) {
						$found{'NOBLESVILLE'}++;
						delta_within($location->{latitude}, 40.0, 1e-1);
						delta_within($location->{longitude}, -86.1, 1e-1);
					}
				}
			}
			ok($found{'GREENWOOD'});
			ok($found{'NOBLESVILLE'});
		} else {
			diag('Set OPENADDR_HOME to scantext testing');
			skip 'OPENADDR_HOME not defined', 14;
		}
	}
}