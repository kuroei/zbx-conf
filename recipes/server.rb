require 'json'
require 'open-uri'
require 'zabbixapi'

json_file_path = '/var/lib/niftycloud/automation/chef/'

files_sort = Dir[json_file_path+"*.json"].sort_by{ |f| File.mtime(f) }
json_file_realpath = files_sort[files_sort.length-1]

json_data = open(json_file_realpath).read
json_result = JSON.parse(json_data)

#p json_result['opsworks']['layers']['zabbix']['instances'][]['ip']

ZABBIX_SERVER = json_result['opsworks']['instances']['ip']
#puts ZABBIX_SERVER
ZABBIX_API_URL = "http://#{ZABBIX_SERVER}/api_jsonrpc.php"
ZABBIX_LOGINID = "admin"
ZABBIX_PASSWORD = "zabbix"

zbx = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_LOGINID, :password => ZABBIX_PASSWORD)
#p zbx.hosts.get("output" => "extend")
#p json_result['opsworks']['layers']['php-app']['instances'].class

# need to get all agent-server before doing-json

ZABBIX_HOSTS_INFO = zbx.hosts.get_full_data(:host => "")

# ZABBIX_HOSTS_INFO.length
# ZABBIX_HOSTS_INFO[0]['host']=="auto2app303"
# ZABBIX_HOSTS_INFO[1]['host']=="auto2app303"
#ABBIX_HOSTS_INFO.delete_if{|x| x['host']=="auto2app303"}
# ZABBIX_HOSTS_INFO.length

# this one used to get the zabbix_agent_layers
#zabbix_agent_layers = json_result['zabbix'][layers]
zabbix_agent_layers = "php-app"

# add the all-in-one group
if zbx.hostgroups.get_id(:name => "all-in-one")==nil
         zbx.hostgroups.create(:name => "all-in-one")
end

layers_all_id = zbx.hostgroups.get_id(:name => "all-in-one")

json_result['opsworks']['layers'].each do |k,v|
  lay_name = k
  if zabbix_agent_layers.include?(lay_name)
        # the lay is the one witch we want to add
        # if not exited
        if zbx.hostgroups.get_id(:name => k)==nil
                #creat the hostgroup for this layer
                zbx.hostgroups.create(:name => k)
        end
        lay_id = zbx.hostgroups.get_id(:name => k)
        # add the server in this layer
        v['instances'].each do |k1,v1|
                php_app_ip = v1['private_ip']
                php_app_host = k1
                #php_app_dns = v1['public_dns_name']
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
                :groups => [
                        {
                        :groupid => lay_id
                        },
                        {
                        :groupid => layers_all_id
                        }
                ]
                )

                zbx.templates.mass_add(
                         :hosts_id => [zbx.hosts.get_id(:host => php_app_host)],
                         :templates_id => [10050,10089]
                )

                # you need delete this server info from the ZABBIX_SERVER_INFO
                ZABBIX_HOSTS_INFO.delete_if{|x| x['host']==php_app_host}
        end
  end

end

p ZABBIX_HOSTS_INFO.length

ZABBIX_HOSTS_INFO.each do |x|
        zbx.hosts.delete zbx.hosts.get_id(:host => x['host'])
end

#p zbx.hosts.get("output" => "extend")
