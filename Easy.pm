
package Net::Pcap::Easy;

use strict;
use Carp;
use Net::Pcap;
use NetPacket::Ethernet qw(:types);
use NetPacket::IP;
use NetPacket::ARP;
use NetPacket::TCP;
use NetPacket::UDP;
use NetPacket::ICMP;

our $VERSION     = "1.0";
our $MIN_SNAPLEN = 256;
our $DEFAULT_PPL = 32;

sub DESTROY {
    my $this = shift;

    Net::Pcap::close($this->{pcap});
}

sub new {
    my $class = shift;
    my $this = bless { @_ }, $class;

    my $err;
    my $dev = ($this->{dev});
    unless( $dev ) {
        $dev = $this->{dev} = Net::Pcap::lookupdev(\$err);
        croak "ERROR while trying to find a device: $err" unless $dev;
    }

    my ($addr, $netmask);
    if (Net::Pcap::lookupnet($dev, \$addr, \$netmask, \$err)) {
        croak "ERROR finding net and netmask for $dev: $err";

    } else {
        $this->{address} = $addr;
        $this->{netmask} = $netmask;
    }

    my $ppl = $this->{packets_per_loop};
       $ppl = $this->{packets_per_loop} = $DEFAULT_PPL unless defined $ppl and $ppl > 0;

    my $ttl = $this->{timeout_in_ms} || 0;
       $ttl = 0 if $ttl < 0;

    my $snaplen = $this->{bytes_to_capture} || 1024;
       $snaplen = $MIN_SNAPLEN unless $snaplen >= 256;

    my $pcap = $this->{pcap} = Net::Pcap::open_live($dev, $snaplen, $this->{promiscuous}, $ttl, \$err);
    croak "ERROR opening pacp session: $err" if $err or not $pcap;

    if( my $f = $this->{filter} ) {
        my $filter;
        Net::Pcap::compile( $pcap, \$filter, $f, 1, $netmask ) && croak 'ERROR compiling pcap filter';
        Net::Pcap::setfilter( $pcap, $filter ) && die 'ERROR Applying pcap filter';
    }

    $this->{_mcb} = sub {
        my ($user_data, $header, $packet) = @_;
        my $ether = NetPacket::Ethernet->decode($packet);

        # :types ETH_TYPE_IP ETH_TYPE_ARP ETH_TYPE_APPLETALK ETH_TYPE_SNMP ETH_TYPE_IPv6 ETH_TYPE_PPP

        my $type = $ether->type;

        $this->ip4(  $user_data, $ether ) if $type eq ETH_TYPE_IP;
        $this->ip6(  $user_data, $ether ) if $type eq ETH_TYPE_IPv6;
        $this->arp(  $user_data, $ether ) if $type eq ETH_TYPE_ARP;
        $this->snmp( $user_data, $ether ) if $type eq ETH_TYPE_SNMP;
        $this->ppp(  $user_data, $ether ) if $type eq ETH_TYPE_PPP;
    };

    return $this;
}

sub loop {
    my $this = shift;

    Net::Pcap::loop($this->{pcap}, $this->{packets_per_loop}, $this->{_mcb}, "user data");
}

"true";
