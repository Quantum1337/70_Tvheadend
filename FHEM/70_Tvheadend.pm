package main;

use strict;
use warnings;

use HttpUtils;
use HTML::Entities;
use utf8;
use JSON;

#my $channelCount = "";
my $state = 0;

my %Tvheadend_sets = (
	"reread:noArg" => "",
);

sub Tvheadend_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Tvheadend_Define';
    $hash->{UndefFn}    = 'Tvheadend_Undef';
    $hash->{SetFn}      = 'Tvheadend_Set';
    $hash->{ShutdownFn} = 'Tvheadend_Shutdown';
    $hash->{AttrFn}     = 'Tvheadend_Attr';
    $hash->{NotifyFn}   = 'Tvheadend_Notify';

    $hash->{AttrList} =
					"primeTime " .
					"ip " .
					"port " .
					"user " .
					"password " .
          $readingFnAttributes;

}

sub Tvheadend_Define($$$) {
	my ($hash, $def) = @_;
	$state = 0;
	return;
}

sub Tvheadend_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash,"Tvheadend_Request");

	return undef;
}

sub Tvheadend_Shutdown($){
	my($hash) = @_;

	RemoveInternalTimer($hash,"Tvheadend_Request");

	return;

}

sub Tvheadend_Set($$$) {
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "reread"){

		$hash->{helper}->{http}->{ip} = AttrVal($hash->{NAME},"ip",undef);
		$hash->{helper}->{http}->{port} = AttrVal($hash->{NAME},"port",undef);
		$hash->{helper}->{http}->{user} = AttrVal($hash->{NAME},"user",undef);
		$hash->{helper}->{http}->{password} = AttrVal($hash->{NAME},"password",undef);

		&Tvheadend_Request($hash);
	}else{
		my @cList = keys %Tvheadend_sets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
	}

}

sub Tvheadend_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;


	return undef
}

sub Tvheadend_Notify($$){
	my ($own_hash, $dev_hash) = @_;


	return
}

sub Tvheadend_Request($){
	my ($hash) = @_;

	$state = 0 if(!$hash->{helper}->{epg}->{count});

	if($state == 0){

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $response;
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),return) if($err);

			eval{
				$response = decode_json($data);
			} or return $@;

			$entries = $response->{entries};

			my $channels = $hash->{helper}->{epg}->{channels};
			for (my $i=0;$i < int(@$entries);$i+=1){
				@$channels[$i] = @$entries[$i]->{val};
			}

			$hash->{helper}->{epg}->{count} = @$entries;
			#RemoveInternalTimer($hash,"Tvheadend_Request");
			InternalTimer(gettimeofday(),"Tvheadend_Request",$hash);
			Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 1");
			$state = 1;
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get Channels");

		my @channels = ();
		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};
		$hash->{helper}->{epg}->{channels} = \@channels;

		$hash->{helper}->{http}->{id} = "";
		$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/channel/list";
		&Tvheadend_HttpGet($hash);

		return;
	}elsif($state == 1){

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $response;
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),return) if($err);

			eval{
				$response = decode_json($data);
			} or return $@;

			$entries = $response->{entries};

			@$entries = sort {$a->{channelNumber} <=> $b->{channelNumber} ||
												$a->{start} <=> $b->{start}
											} @$entries;

			$hash->{helper}->{epg}->{update} = @$entries[0]->{stop};

			for (my $i=0;$i < int(@$entries);$i+=1){
					$hash->{helper}->{epg}->{update} = @$entries[$i]->{stop} if(@$entries[$i]->{stop} < $hash->{helper}->{epg}->{update});
					$hash->{helper}->{epg}->{now} = $entries;
			}

			#RemoveInternalTimer($hash,"Tvheadend_Request");
			InternalTimer(gettimeofday(),"Tvheadend_Request",$hash) if ($state == 1);
			Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 2");
			$state = 2;

		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Now");

		my $count = $hash->{helper}->{epg}->{count};
		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};

		$hash->{helper}->{http}->{id} = "";
		$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/grid?limit=$count";
		&Tvheadend_HttpGet($hash);

		return;
	}elsif($state == 2){

		$hash->{helper}->{http}->{callback} = sub{
			my ($param, $err, $data) = @_;

			my $hash = $param->{hash};
			my $response;
			my $entries;

			(Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - $err"),return) if($err);

			eval{
				$response = decode_json($data);
			} or return $@;

			$entries = $response->{entries};

			my $entriesNext = $hash->{helper}->{epg}->{next};
			@$entriesNext[$param->{id}] = @$entries[0];

			#Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - ".scalar(grep {defined $_} @$entriesNext)." / $hash->{helper}->{epg}->{count}");
			if(scalar(grep {defined $_} @$entriesNext) == $hash->{helper}->{epg}->{count}){
				#RemoveInternalTimer($hash,"Tvheadend_Request");
				InternalTimer(gettimeofday(),"Tvheadend_Request",$hash);
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Set State 3");
				$state = 3;
			}
		};

		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Get EPG Next");

		my @entriesNext = ();
		my $entries = $hash->{helper}->{epg}->{now};
		my $count = $hash->{helper}->{epg}->{count};
		my $ip = $hash->{helper}->{http}->{ip};
		my $port = $hash->{helper}->{http}->{port};

		$hash->{helper}->{epg}->{next} = \@entriesNext;

		for (my $i=0;$i < int($count);$i+=1){
			$hash->{helper}->{http}->{id} = $i;
			$hash->{helper}->{http}->{url} = "http://".$ip.":".$port."/api/epg/events/load?eventId=".@$entries[$i]->{nextEventId};
			&Tvheadend_HttpGet($hash);
		}
		return;
	}elsif($state == 3){
		my $update = $hash->{helper}->{epg}->{update};
		my $entriesNow = $hash->{helper}->{epg}->{now};
		my $entriesNext = $hash->{helper}->{epg}->{next};
		my $channels = $hash->{helper}->{epg}->{channels};

		readingsBeginUpdate($hash);
		for (my $i=0;$i < int(@$entriesNow);$i+=1){
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."Name", @$entriesNow[$i]->{channelName});
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."Number", @$entriesNow[$i]->{channelNumber});
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."TitleNow", @$entriesNow[$i]->{title});
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."StartNow", strftime("%H:%M:%S",localtime(@$entriesNow[$i]->{start})));
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."EndNow", strftime("%H:%M:%S",localtime(@$entriesNow[$i]->{stop})));
				readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."DescriptionNow", @$entriesNow[$i]->{description});
		}

		for (my $i=0;$i < int(@$entriesNext);$i+=1){
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."DescriptionNext", @$entriesNext[$i]->{description});
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."TitleNext", @$entriesNext[$i]->{title});
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."StartNext", strftime("%H:%M:%S",localtime(@$entriesNext[$i]->{start})));
			readingsBulkUpdateIfChanged($hash, "channel".sprintf("%02d", $i)."EndNext", strftime("%H:%M:%S",localtime(@$entriesNext[$i]->{stop})));
		}
		readingsEndUpdate($hash, 1);

		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Next update: ".  strftime("%H:%M:%S",localtime($update)));
		RemoveInternalTimer($hash,"Tvheadend_Request");
		InternalTimer($update + 10,"Tvheadend_Request",$hash);
		$state = 1;
	}

}


sub Tvheadend_HttpGet($){
	my ($hash) = @_;

	HttpUtils_NonblockingGet(
		{
				method     => "GET",
				url        => $hash->{helper}->{http}->{url},
				timeout    => "20",
				user			 => $hash->{helper}->{http}->{user},
				pwd				 => $hash->{helper}->{http}->{password},
				noshutdown => "1",
				hash			 => $hash,
				id				 => $hash->{helper}->{http}->{id},
				callback   => $hash->{helper}->{http}->{callback}
		});

}
