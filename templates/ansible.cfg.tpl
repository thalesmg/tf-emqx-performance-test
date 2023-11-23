[defaults]
inventory=./ansible/inventory.ini
roles_path=./ansible/roles
private_key_file=${private_key_file}
remote_user=${remote_user}
host_key_checking=False
use_persistent_connections=True
strategy=free

[connection]
pipelining=True

[persistent_connection]
control_path_dir={{ ANSIBLE_HOME ~ "/pc" }}
