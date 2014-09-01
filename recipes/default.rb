#
# Cookbook Name:: test
# Recipe:: default
#
# Copyright 2014, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute

r = gem_package "zabbixapi" do
  action :install
end

