import yaml

with open('matrix/homeserver.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Enable CORS for Element
config['enable_cors'] = True

# Ensure Synapse binds to 0.0.0.0 so Caddy can reach it
for listener in config.get('listeners', []):
    if listener.get('port') == 8008:
        listener['bind_addresses'] = ['0.0.0.0']

with open('matrix/homeserver.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
