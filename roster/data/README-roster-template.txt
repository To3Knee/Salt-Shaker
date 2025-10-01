Salt-SSH Roster CSV Editing Guide
================================

This guide explains how to edit salt-shaker/roster/data/hosts-all-pods.csv for Salt-SSH roster configuration.

1. File Location:
   - CSV file: /sto/salt-shaker/roster/data/hosts-all-pods.csv
   - Format: Comma-separated values (CSV) with 10 fields

2. Fields Description:
   - pod: Environment identifier (e.g., prod, dev, test)
   - target: Unique alias for Salt commands (e.g., web-01-prod)
   - host: Hostname or IP address (e.g., web-01.prod.example.com)
   - ip: IP address (optional if host is an IP)
   - port: SSH port (default: 22)
   - user: SSH username (e.g., admin, root)
   - passwd: SSH password (replace <YOUR_PASSWORD> or use pillar for security)
   - sudo: TRUE/FALSE for sudo access
   - ssh_args: Additional SSH arguments (e.g., -o StrictHostKeyChecking=no)
   - description: Human-readable description (e.g., Web server in prod)

3. Editing Instructions:
   - Excel:
     * Open the CSV in Excel.
     * Ensure comma delimiter and UTF-8 encoding are selected.
     * Replace sample data (e.g., <YOUR_PASSWORD>, 10.0.0.x) with actual values.
     * Save as CSV without changing the format.
   - Linux:
     * Use vi, nano, or any text editor (e.g., nano salt-shaker/roster/data/hosts-all-pods.csv).
     * Replace sample data with actual values.
     * Avoid commas in field values to prevent parsing issues.
     * Save with Unix line endings (\n).
   - Security:
     * Avoid storing plaintext passwords in the passwd field.
     * Consider using Salt pillar or encrypted storage for credentials.
     * Set file permissions to 644 (chmod 644 salt-shaker/roster/data/hosts-all-pods.csv).

4. Example Entry:
   prod,web-01-prod,web-01.prod.example.com,10.0.0.10,22,admin,securepass,TRUE,-o StrictHostKeyChecking=no,Web server in production

5. Next Steps:
   - Run 06-check-vendors.sh to validate the build.
   - Run 07-remote-test.sh to test remote connectivity.
   - Run 08-generate-configs.sh to generate the roster file from this CSV.

6. Troubleshooting:
   - Check logs: salt-shaker/logs/salt-shaker.log, salt-shaker/logs/salt-shaker-errors.log
   - Ensure no commas in field values.
   - Verify SSH access to hosts before running 07-remote-test.sh.

Created: 09/28/2025
Version: 2.5
