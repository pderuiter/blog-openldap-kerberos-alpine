# blog-openldap-kerberos-alpine

Companion code for the blog post
[Setting Up OpenLDAP and Kerberos on Alpine Linux with Ansible](https://blog.bsdserver.nl/setting-up-openldap-and-kerberos-on-alpine-linux-with-ansible/).

It builds the two-node identity platform from the post on Alpine Linux 3.23:

- OpenLDAP with cn=config, MDB and multi-provider syncrepl over LDAPS
- MIT Kerberos with its principal database in LDAP (kldap), so syncrepl replicates principals and no kprop is needed
- nslcd + musl-nscd for users and groups, SSH public keys from LDAP and sudo for an LDAP group
- nftables with a default-drop policy
- daily backups

glibc clients (Ubuntu/Debian, RHEL/Rocky) can join through SSSD.

## What's in here

| Path | What it does |
| --- | --- |
| `terraform/` | Alpine 3.23 VMs on Proxmox VE from the official cloud image (bpg/proxmox). cloud-init installs Python and sudo for Ansible. Outputs an Ansible inventory. |
| `ansible/roles/firewall` | nftables, default-drop input. TCP 22, 389, 636, 88, 749 and UDP 88 are open. |
| `ansible/roles/base` | Packages, chrony, an organization CA on the control node (`community.crypto`), and per-host certificates signed by it. Idempotent: an existing certificate is only re-issued when it no longer matches. |
| `ansible/roles/openldap` | The post's three-phase bootstrap. Phase 1 is `slapadd -n0` with core schemas, MDB, basic ACLs, syncprov and `olcMultiProvider`. Phase 2 loads the Kerberos, openssh-lpk and sudoers schemas with `slapadd`. Phase 3 applies the full ACLs with `ldapmodify`. Also creates the initial DIT, the service accounts and their passwords. |
| `ansible/roles/kerberos` | `krb5.conf` with the `[dbmodules]` block from the post, `stashsrvpw` for both service DNs, realm creation on the first node, a master key stash on the others, and a `krb5kdc` init script that needs slapd. |
| `ansible/roles/ldap_client` | Dispatches on `os_family`. Alpine gets nslcd + musl-nscd, `nsswitch.conf`, an nscd init script with hard dependencies, the `AuthorizedKeysCommand` script and a sudoers drop-in. Debian/Ubuntu and RHEL/Rocky get SSSD with LDAP identity, krb5 auth, LDAP sudo rules and SSH keys. |
| `ansible/roles/backup` | Daily 02:00 cron job: LDAP data and OLC config as LDIF, Kerberos stash files and the principal list, and config files. Keeps 30 days. |
| `ansible/site.yml` | Builds the whole setup: infra nodes one at a time, then any `ldap_clients`. |

The post calls the client role `ldap-client`. It is `ldap_client` here because ansible-lint does not allow dashes in role names.

## Requirements

- Proxmox VE with a datastore that allows the `snippets` content type (for the cloud-init user-data), and an API token
- Terraform >= 1.6
- Ansible >= 2.16 (ansible-core) with the collections in `ansible/requirements.yml`, plus `python3-cryptography` on the control node
- Name resolution for the node FQDNs (`infra04.example.com`, ...) on the nodes and clients, via DNS or `/etc/hosts`.
  The certificates, syncrepl and Kerberos all use these names.

## Quick start

```bash
# 1. Machines
cd terraform
cp terraform.tfvars.example terraform.tfvars   # endpoint, token, node, IPs, SSH key, domain
terraform init
terraform apply
terraform output -raw ansible_inventory > ../ansible/inventory.yml

# 2. Configuration
cd ../ansible
ansible-galaxy collection install -r requirements.yml
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml   # LDAP admin, Kerberos master, service accounts, CA passphrase
ansible-playbook site.yml --ask-vault-pass
```

Without Terraform, use `ansible/inventory.example.yml`. Put the LDAP/KDC nodes in `infra`, with FQDNs as inventory
names, and glibc clients in `ldap_clients`. The first host in `infra` loads the initial data and creates the realm.
The others get everything through syncrepl.

The CA key and certificate are created in `ansible/files/ca/` on the control node, which is ignored by git. Keep them
safe; they sign every node certificate.

## Daily operations

Adding a user works exactly as in the post. Run these commands on any node:

```bash
ldapadd -x -D "cn=admin,dc=example,dc=com" -W -H ldap://localhost <<EOF
dn: uid=jdoe,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: ldapPublicKey
uid: jdoe
cn: Jane Doe
sn: Doe
givenName: Jane
uidNumber: 10001
gidNumber: 10000
homeDirectory: /home/jdoe
loginShell: /bin/bash
sshPublicKey: ssh-ed25519 AAAA... jane@example.com
EOF
kadmin.local -q "addprinc jdoe@EXAMPLE.COM"
ldapmodify -x -D "cn=admin,dc=example,dc=com" -W -H ldap://localhost <<EOF
dn: cn=admins,ou=Groups,dc=example,dc=com
changetype: modify
add: memberUid
memberUid: jdoe
EOF
```

The base role installs `bash`, because Alpine doesn't ship it and sshd refuses a user whose shell is missing.

## Variables

The main ones are in `ansible/group_vars/all/vars.yml`. Secrets come from `vault.yml` (`vault_` prefix).

| Variable | Default | Meaning |
| --- | --- | --- |
| `ldap_base` | `dc=example,dc=com` | Directory suffix |
| `krb_realm` | `EXAMPLE.COM` | Kerberos realm |
| `ldap_servers` | `groups['infra']` | LDAP/KDC nodes (FQDNs) |
| `ldap_server_id` | position in `ldap_servers` | `olcServerID`, per host |
| `tls_organization_name` | `Example Org` | Organization in the CA and host certificates |
| `ldap_admins_group` / `ldap_admins_gid` | `admins` / `10000` | Group that gets sudo |
| `base_chrony_enabled` | `true` | Kerberos needs synchronized clocks |
| `firewall_tcp_ports` / `firewall_udp_ports` | post's port list | Open ports |
| `backup_dir` / `backup_retention_days` | `/var/backups/ldap` / `30` | Backup location and retention |

## Tested

In the lab, two Alpine 3.23 containers ran real OpenRC with `NET_ADMIN` for nftables. An Ubuntu 24.04 systemd
container acted as the SSSD client. Tools: ansible-core 2.16 (Ansible 9.13.0), OpenLDAP 2.6.13, MIT Kerberos 1.22.3.

- First run completes, second run reports `changed=0`.
- Bound `ldapsearch` over LDAPS works on both nodes.
- Replication works both ways.
- `kinit`/`klist` works on both nodes and on the client.
- `getent`/`id` resolve via musl-nscd and via SSSD.
- SSH login with the LDAP-stored key and passwordless sudo works for the `admins` group on all three machines.
- The firewall drops a non-listed port.
- The backup script produces its files.

The containers skipped two things: setting the hostname and running chrony (`base_manage_hostname` and
`base_chrony_enabled` were set to false). The RHEL/Rocky client tasks are linted but were not run.

`ansible-lint` (production profile), `yamllint`, `terraform fmt -check`, `terraform validate` and `tflint` are clean.
Terraform has not been applied as part of these tests.

## License

MIT
