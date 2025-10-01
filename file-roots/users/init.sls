{# Minimal example using pillar-driven password hashes #}
users:
  shaker_admin:
    present: true
    fullname: 'Shaker Admin'
    shell: /bin/bash
    password: {{ pillar.get('users', {}).get('shaker_admin', {}).get('password', '!!') }}
