package main;

use strict;
use warnings;

my %Tvheadend_sets = (
	"timer" => "",
);

sub Tvheadend_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Tvheadend_Define';
    $hash->{UndefFn}    = 'Tvheadend_Undef';
    $hash->{SetFn}      = 'Tvheadend_Set';
    $hash->{ShutdownFn} = 'Tvheadend_Shutdown';
    $hash->{ReadFn}     = 'Tvheadend_Read';
    $hash->{AttrFn}     = 'Tvheadend_Attr';
    $hash->{NotifyFn}   = 'Tvheadend_Notify';


    $hash->{AttrList} =
					"primeTime " .
          $readingFnAttributes;

}

sub Tvheadend_Define($$$) {
	my ($hash, $def) = @_;

	return
}

sub Tvheadend_Undef($$) {
	my ($hash, $arg) = @_;


	return undef;
}

sub Tvheadend_Shutdown($){
	my($hash) = @_;


	return;

}

sub Tvheadend_Set($$$) {
	my ($hash, $name, $opt, @args) = @_;

	my @cList = keys %Tvheadend_sets;
	return "Unknown command $opt, choose one of " . join(" ", @cList);
}

sub Tvheadend_Read($){
	my ( $hash ) = @_;


}

sub Tvheadend_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;


	return undef
}

sub Tvheadend_Notify($$){
	my ($own_hash, $dev_hash) = @_;


	return
}
