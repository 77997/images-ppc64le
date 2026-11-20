"""Fails the build when an installed distribution's files are not its own.

pip installs each distribution over whatever is already there, so a file two distributions both list in their RECORD
holds the content of whichever was installed last, and pip check, which reads only metadata, still passes. Checked in
Zuul's own environment and in each Ansible environment zuul-manage-ansible built, which pip check also reads.
"""

import csv
import glob
import os
import subprocess
import sys
import sysconfig

environments = [(None, sysconfig.get_paths()["purelib"])]
for root in sorted(glob.glob("/usr/local/lib/zuul/ansible/*/")):
    environments += [(os.path.join(root, "bin", "python"), sp) for sp in glob.glob(root + "lib/python3*/site-packages")]
if len(environments) < 2:
    sys.exit("No Ansible environment found under /usr/local/lib/zuul/ansible")

failed = False
for python, site_packages in environments:
    owners = {}
    for record in glob.glob(os.path.join(site_packages, "*.dist-info", "RECORD")):
        distribution = os.path.basename(os.path.dirname(record))
        with open(record, newline="") as f:
            for row in csv.reader(f):
                if row and not row[0].startswith("..") and ".dist-info/" not in row[0]:
                    owners.setdefault(row[0], set()).add(distribution)
    shared = {path: sorted(o) for path, o in owners.items() if len(o) > 1}
    for path, o in sorted(shared.items())[:20]:
        print(f"{site_packages}: {path} is listed by {', '.join(o)}")
    # The builder's own environment also holds its build tools, so pip check reads the Ansible environments alone.
    check = subprocess.run([python, "-m", "pip", "check"], capture_output=True, text=True) if python else None
    if check and check.returncode != 0:
        print(f"{site_packages}: pip check failed:\n{check.stdout}{check.stderr}")
    failed |= bool(shared) or bool(check and check.returncode != 0)
    print(f"{site_packages}: {len(owners)} files, {len(shared)} listed by two distributions"
          + (f", pip check {check.returncode}" if check else ""))
sys.exit(1 if failed else 0)
