import yaml
with open('matrix/homeserver.yaml', 'r') as f:
    config = yaml.safe_load(f)

if 'database' in config and 'args' in config['database']:
    config['database']['args']['allow_unsafe_locale'] = True

with open('matrix/homeserver.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
