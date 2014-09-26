require 'json'
require 'open-uri'
require 'zabbixapi'

json_file_path = '/var/lib/niftycloud/automation/chef/'

files_sort = Dir[json_file_path+"*.json"].sort_by{ |f| File.mtime(f) }
json_file_realpath = files_sort[files_sort.length-1]

Chef::Log.info json_file_realpath

json_data = open(json_file_realpath).read
JSON_RESULT = JSON.parse(json_data)

ZABBIX_SERVER = JSON_RESULT['opsworks']['instance']['ip']
ZABBIX_API_URL = "http://#{ZABBIX_SERVER}/api_jsonrpc.php"
ZABBIX_LOGINID = JSON_RESULT['zabbix']['automation']['zbxuser']
ZABBIX_PASSWORD = JSON_RESULT['zabbix']['automation']['zbxpw']
ZABBIX_ADMIN_PASSWORD = JSON_RESULT['zabbix']['automation']['zbxadminpw']
ZABBIX_ADMIN = "Admin"
ZABBIX_ADMIN_PASSWORD_OLD = "zabbix"

ZABBIX_ADMIN_GROUP = "Zabbix administrators"

ZABBIX_HOSTGROUP_ALL = "all-in-one"

LOGIN_WITH_NOMAL = 0
LOGIN_WITH_ADMIN = 1
LOGIN_WITH_ADMIN_OLD = 2
LOGIN_FAIL = -1
LOGIN_OVER = 100

def createUser(zbx)
 # create user for automation
 zbx.users.create_or_update(
  :alias => ZABBIX_LOGINID,
  :name => Time.now,
  :surname => ZABBIX_LOGINID,
  :passwd => ZABBIX_PASSWORD, 
  :usrgrps => [
            {
                :usrgrpids => [zbx.usergroups.get_id(:name => ZABBIX_ADMIN_GROUP)]
            }
   ],
  :type => 3
 )
 
 # update the password
# zbx.users.update(:userid => zbx.users.get_id(:alias => ZABBIX_LOGINID), :name => ZABBIX_LOGINID, :passwd => ZABBIX_PASSWORD)

 # add automation user to zabbix admin group
 zbx.usergroups.get_or_create(:name => ZABBIX_ADMIN_GROUP)
 zbx.usergroups.add_user(
  :usrgrpids => [zbx.usergroups.get_id(:name => ZABBIX_ADMIN_GROUP)],
  :userids => [zbx.users.get_id(:alias => ZABBIX_LOGINID)]
)

 #set the perms for groups
 zbx.usergroups.set_perms(
   :usrgrpid => zbx.usergroups.get_or_create(:name => ZABBIX_ADMIN_GROUP),
   :hostgroupids => zbx.hostgroups.all.values, # kind_of Array
   :permission => 3 # 2- read (by default) and 3 - write and read
)

end

# update the admin user's pw
def updateAdminpw(zbx)
zbx.users.update(:userid => zbx.users.get_id(:alias => ZABBIX_ADMIN), :name => Time.now, :passwd => ZABBIX_ADMIN_PASSWORD)
end

# update the json info to zabbix server
def updateInfo(zbx)
# zbx = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_LOGINID, :password => ZABBIX_PASSWORD)
#p zbx.hosts.get("output" => "extend")

# need to get all agent-server before doing-json

zabbix_hosts_info = zbx.hosts.get_full_data(:host => "")

# this one used to get the zabbix_agent_layers
zabbix_agent_layers = JSON_RESULT['opsworks']['layers']

# add the ZABBIX_HOSTGROUP_ALL group
if zbx.hostgroups.get_id(:name => ZABBIX_HOSTGROUP_ALL)==nil
         zbx.hostgroups.create(:name => ZABBIX_HOSTGROUP_ALL)
         #Chef::Log.info 'Zabbix-server: create the hostsgroup [all-in-one]'
end

layers_all_id = zbx.hostgroups.get_id(:name => ZABBIX_HOSTGROUP_ALL)

JSON_RESULT['opsworks']['layers'].each do |k,v|
 lay_name = k
 # if zabbix_agent_layers.include?(lay_name)
        # the lay is the one witch we want to add
        # if not exited
        if zbx.hostgroups.get_id(:name => k)==nil
                #creat the hostgroup for this layer
                zbx.hostgroups.create(:name => k)
        end
        lay_id = zbx.hostgroups.get_id(:name => k)
        # add the server in this layer
        v['instances'].each do |k1,v1|
                server_ip = v1['private_ip']
                server_host = k1
                #server_dns can't be nil
                server_dns = ''
                zbx.hosts.create_or_update(
                :host => server_host,
                :interfaces => [
                        {
                        :type => 1,
                        :main => 1,
                        :ip => server_ip,
                        :dns => server_dns,
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

                #p "#{server_host}->#{lay_id},#{layers_all_id}"
                zbx.templates.mass_add(
                         :hosts_id => [zbx.hosts.get_id(:host => server_host)],
                         :templates_id => [10050,10089]
                )

                # you need delete this server info from the ZABBIX_SERVER_INFO
                zabbix_hosts_info.delete_if{|x| x['host']==server_host}
        end
  #end

end


zabbix_hosts_info.each do |x|
        zbx.hosts.delete zbx.hosts.get_id(:host => x['host'])
end

end

# choose the way
# LOGIN_WITH_NOMAL = 0
# LOGIN_WITH_ADMIN = 1
# LOGIN_WITH_ADMIN_OLD = 2
# LOGIN_FAIL = -1
# LOGIN_OVER = 100
def checkState(state)
  if state == LOGIN_WITH_NOMAL
    zabbixserver = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_LOGINID, :password => ZABBIX_PASSWORD)
    updateInfo(zabbixserver)
  elsif state == LOGIN_WITH_ADMIN
    zabbixserver = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_ADMIN, :password => ZABBIX_ADMIN_PASSWORD)
    createUser(zabbixserver)
  elsif state == LOGIN_WITH_ADMIN_OLD
    zabbixserver = ZabbixApi.connect(:url => ZABBIX_API_URL, :user => ZABBIX_ADMIN, :password => ZABBIX_ADMIN_PASSWORD_OLD)
    createUser(zabbixserver)
    updateAdminpw(zabbixserver)
  else
        Chef::Log.info 'there is any users for automation to setup zabbix'
  end
end

# add the process from here
ZABBIX_STATE = LOGIN_WITH_NOMAL

while ZABBIX_STATE != LOGIN_FAIL && ZABBIX_STATE != LOGIN_OVER do
        begin
                checkState(ZABBIX_STATE)
                if ZABBIX_STATE == LOGIN_WITH_NOMAL
                        ZABBIX_STATE = LOGIN_OVER
                elsif ZABBIX_STATE == LOGIN_WITH_ADMIN
                        ZABBIX_STATE = LOGIN_WITH_NOMAL
                else
                        ZABBIX_STATE = LOGIN_WITH_NOMAL
                end
                rescue => ex
                Chef::Log.info ex.message
                p ex.message
                if ZABBIX_STATE == LOGIN_WITH_NOMAL then
                        ZABBIX_STATE = LOGIN_WITH_ADMIN
                elsif ZABBIX_STATE == LOGIN_WITH_ADMIN
                        ZABBIX_STATE = LOGIN_WITH_ADMIN_OLD
                else
                        ZABBIX_STATE = LOGIN_FAIL
                end
        end
end

