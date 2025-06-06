##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'CouchDB Login Utility',
        'Description' => %q{
          This module tests CouchDB logins on a range of
          machines and report successful logins.
        },
        'Author' => [
          'espreto <robertoespreto[at]gmail.com>'
        ],
        'License' => MSF_LICENSE,
        'Notes' => {
          'Stability' => [CRASH_SAFE],
          'SideEffects' => [IOC_IN_LOGS, ACCOUNT_LOCKOUTS],
          'Reliability' => []
        }
      )
    )

    register_options(
      [
        Opt::RPORT(5984),
        OptString.new('TARGETURI', [false, 'TARGETURI for CouchDB. Default here is /', '/']),
        OptPath.new('USERPASS_FILE', [
          false, 'File containing users and passwords separated by space, one pair per line',
          File.join(Msf::Config.data_directory, 'wordlists', 'http_default_userpass.txt')
        ]),
        OptPath.new('USER_FILE', [
          false, 'File containing users, one per line',
          File.join(Msf::Config.data_directory, 'wordlists', 'http_default_users.txt')
        ]),
        OptPath.new('PASS_FILE', [
          false, 'File containing passwords, one per line',
          File.join(Msf::Config.data_directory, 'wordlists', 'http_default_pass.txt')
        ]),
        OptBool.new('USER_AS_PASS', [ false, 'Try the username as the password for all users', false]),
      ]
    )

    deregister_options('HttpUsername', 'HttpPassword')
  end

  def run_host(_ip)
    user = datastore['HttpUsername'].to_s
    pass = datastore['HttpPassword'].to_s

    if user.nil? || user.strip == ''
      each_user_pass do |u, p|
        do_login(u, p)
      end
      return
    end

    vprint_status("#{rhost}:#{rport} - Trying to login with '#{user}' : '#{pass}'")

    uri = target_uri.path

    res = send_request_cgi({
      'uri' => normalize_uri(uri, '_users/_all_docs'),
      'method' => 'GET',
      'authorization' => basic_auth(user, pass)
    })

    return if res.nil?
    return if res.headers['Server'].nil? || res.headers['Server'] !~ /CouchDB/
    return if res.code == 404

    if [200, 301, 302].include?(res.code)
      vprint_good("#{rhost}:#{rport} - Successful login with '#{user}' : '#{pass}'")
    end
  rescue ::Rex::ConnectionError
    vprint_error("'#{rhost}':'#{rport}' - Failed to connect to the web server")
  end

  def report_cred(opts)
    service_data = {
      address: opts[:ip],
      port: opts[:port],
      service_name: opts[:service_name],
      protocol: 'tcp',
      workspace_id: myworkspace_id
    }

    credential_data = {
      origin_type: :service,
      module_fullname: fullname,
      username: opts[:user],
      private_data: opts[:password],
      private_type: :password
    }.merge(service_data)

    login_data = {
      core: create_credential(credential_data),
      status: Metasploit::Model::Login::Status::UNTRIED,
      proof: opts[:proof]
    }.merge(service_data)

    create_credential_login(login_data)
  end

  def do_login(user, pass)
    vprint_status("Trying username:'#{user}' with password:'#{pass}'")

    res = send_request_cgi({
      'uri' => normalize_uri(target_uri.path, '_users/_all_docs'),
      'method' => 'GET',
      'ctype' => 'text/plain',
      'authorization' => basic_auth(user, pass)
    })

    unless res
      print_error('HTTP connection failed, aborting')
      return :abort
    end

    return :skip_pass unless res.code == 200

    print_good("#{peer} - Successful login with: '#{user}' : '#{pass}'")

    report_cred(
      ip: rhost,
      port: rport,
      service_name: 'couchdb',
      user: user,
      password: pass,
      proof: res.code.to_s
    )

    :next_user
  rescue ::Rex::ConnectionError, ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT
    print_error('HTTP connection failed, aborting')
    return :abort
  rescue StandardError => e
    print_error("Error: #{e}")
    return nil
  end
end
