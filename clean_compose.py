import yaml

with open('devops/docker-compose.yml.remote', 'r') as f:
    data = yaml.safe_load(f)

# Keep only one instance of each service
seen_services = set()
services_to_remove = []

for svc_name in list(data['services'].keys()):
    if svc_name in seen_services:
        services_to_remove.append(svc_name)
    else:
        seen_services.add(svc_name)
        
for svc in services_to_remove:
    del data['services'][svc]

# Write back cleanly
class CustomDumper(yaml.Dumper):
    def ignore_aliases(self, data):
        return True

with open('devops/docker-compose.yml', 'w') as f:
    yaml.dump(data, f, Dumper=CustomDumper, default_flow_style=False, sort_keys=False)
