require 'json'
require 'open-uri'
require 'zabbixapi'

json_file_path = '/var/lib/niftycloud/automation/chef/'

files_sort = Dir[json_file_path+"*.json"].sort_by{ |f| File.mtime(f) }
json_file_realpath = files_sort[files_sort.length-1]

json_data = open(json_file_realpath).read
json_result = JSON.parse(json_data)

#p json_result['opsworks']['layers']['zabbix']['instances'][]['ip']

ZABBIX_SERVER = json_result['opsworks']['layers']['zabbix']['instances']['auto2cst002']['ip']
#puts ZABBIX_SERVER
ZABBIX_API_URL = "http://#{ZABBIX_SERVER}/api_jsonrpc.php"
ZABBIX_LOGINID = "admin"
ZABBIX_PASSWORD = "zabbix"

zbx = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_LOGINID, :password => ZABBIX_PASSWORD)
#p zbx.hosts.get("output" => "extend")
#p json_result['opsworks']['layers']['php-app']['instances'].class

# i need to get the every servser's ip from php-app layer
json_result['opsworks']['layers']['php-app']['instances'].each do |k,v|

php_app_ip = v['private_ip']
php_app_host = k
#php_app_dns = v['public_dns_name']
php_app_dns = ''

zbx.hosts.create_or_update(
  :host => php_app_host,
  :interfaces => [
    {
      :type => 1,
      :main => 1,
      :ip => php_app_ip,
      :dns => php_app_dns,
      :port => 10050,
      :useip => 1
    }
  ],
  :groups => [ :groupid => zbx.hostgroups.get_id(:name => "Virtual machines") ]
)
end

p zbx.hosts.get("output" => "extend")
