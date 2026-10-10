# omarchy-custom

SDDM theme cloned from Omarchy, with user and session dropdowns under a
centered login.

![omarchy-custom greeter](preview-2.png)

## Demo

https://github.com/user-attachments/assets/da1df4d0-ea7e-420d-beaf-323579d93e03

Repo: https://github.com/nightdevil00/omarchy-custom

## Install from git

```bash
git clone https://github.com/nightdevil00/omarchy-custom.git
cd omarchy-custom
./install.sh
```

Options:

- `--dry-run` — print what would be done
- `--no-enable` — copy files but don't write `/etc/sddm.conf.d/zz-omarchy-custom-theme.conf`
- `--keep-autologin` — don't remove `/etc/sddm.conf.d/autologin.conf`
- `-h, --help` — usage

## All-in-one: theme + user

One call installs the theme, creates a user, sets its password, and
optionally adds groups and grants sudo. This example creates an administrator:

```bash
./install.sh --add-user alice --groups wheel --sudo
```

- `--groups <g1,g2>` — supplementary groups (default: none); must exist.
  A plain user needs none. `wheel` makes the user an administrator: wheel
  members can become root through polkit (`pkexec`, `run0`) with their own
  password, with or without `--sudo`.
- `--sudo` — sudo with password; `--sudo-nopasswd` — passwordless sudo
  (less secure; stock Omarchy asks for a password). Both write
  `/etc/sudoers.d/<name>`.
- `--skip-password` — don't touch the password (groups/sudo only).
- Existing users are kept and just updated (groups re-applied).
- New users are refused if `/etc/sudoers.d/<name>` already exists, even
  without a sudo flag; inspect and remove the stale file first.

The script resolves theme sources relative to itself, so it works from any
clone path. Existing installs are backed up to `/var/backups/omarchy-custom-sddm/`.

Takes effect on next SDDM greeter (logout/reboot). Test now (logs you out):

```bash
sudo systemctl restart sddm
```

See [multi-user.md](multi-user.md) for multi-user setup: adding users with
groups/sudo, disabling autologin, and troubleshooting.

## User admin scripts (`bin/`)

Standalone admin tools in the Omarchy CLI style (gum TUI, `omarchy:` metadata,
logo via `omarchy-show-logo` when on Omarchy). Separate flow from `install.sh`,
written so they could be proposed upstream:

| Script | Does |
| ------ | ---- |
| `bin/omarchy-add-user` | Create a user: gum prompts for name, group checklist (none by default), sudo level, then `passwd` |
| `bin/omarchy-remove-user` | Remove a user (never root/system/self), optionally home + managed sudo grant |
| `bin/omarchy-set-privileges` | Set sudo level: `password`, `nopasswd`, or `none` (validated drop-in) |
| `bin/omarchy-change-groups` | Change supplementary groups: checklist, `--add`, `--remove`, or `--set` |

```bash
./bin/omarchy-add-user                        # fully interactive
./bin/omarchy-add-user alice --groups wheel --sudo --yes   # scripted
./bin/omarchy-set-privileges alice --level nopasswd --yes
./bin/omarchy-change-groups alice --add docker --yes
./bin/omarchy-remove-user alice --remove-home --yes
```

Every destructive step confirms (bypass with `--yes`); every sudoers write is
`visudo -c` validated. The tools replace or remove only a drop-in containing
exactly one rule they recognize. `omarchy-set-privileges --level none` also
checks effective sudo access afterward: it warns if another rule still grants
it, confirms when none remains, and says so when it could not verify.
Removing your own sudo or `wheel` membership, or the last administrator (a
login user in `wheel` or with an unrestricted sudo grant; a rule limited to
some commands does not count), needs a separate
`--force-lockout` flag; `--yes` alone does not bypass that guard. These guards also apply when the user has a managed sudo drop-in. Run `--help` on any script for its usage.

### Handling privilege warnings

- **Sudo still works after `--level none`:** The tool removed only its own
  drop-in. Run `sudo -l -U <username>` from an administrator session, review
  `/etc/sudoers` and `/etc/sudoers.d/` for the other grant, and edit its source
  with `sudo visudo` (or `sudo visudo -f <file>` for a drop-in). Run the check
  again. Do not assume the user has lost sudo until it reports no grant.
- **An unfamiliar sudoers file blocks a change:** Inspect the named file with
  `sudo visudo -f <file>`. Resolve its rules manually before retrying; the
  tools will not delete or replace rules they do not own. For a theme install,
  omit `--sudo`/`--sudo-nopasswd` if no sudo change is needed.
- **`omarchy-remove-user` warns that a sudoers file was left in place:** The
  file changed while the account was being removed, so the tool did not delete
  it. The account is gone; inspect the file with `sudo visudo -f <file>` and
  remove it manually before reusing that login name.
- **`omarchy-add-user` refuses because a sudoers file already exists:** A
  drop-in left under that name would give the new account sudo. Inspect it
  with `sudo visudo -f <file>`, remove it, then create the user.
- **A lockout guard stops a change:** Add another login user to `wheel` and
  verify that account can administer the machine, then retry. For your own
  sudo or `wheel` removal, make the change from that other account. Use
  `--force-lockout` only when you have a tested recovery path.
- **The post-removal sudo check reports "Could not verify":** The drop-in was
  removed, but `sudo -l` failed for another reason (shown in the message). Run
  `sudo -l -U <username>` from a root shell or another administrator session.
  A failed check does not prove that access was removed.

### Walkthrough (screenshots)

Full run with a demo user, every screen captured in [`screenshots/`](screenshots/):

**`omarchy-add-user`** — username prompt, group checklist, sudo level,
summary confirm, password prompt, done:

![username](screenshots/01-add-username.png)
![groups](screenshots/02-add-groups.png)
![sudo](screenshots/03-add-sudo.png)
![confirm](screenshots/04-add-confirm.png)
![password](screenshots/05-add-password.png)
![done](screenshots/06-add-done.png)

**`omarchy-set-privileges`** — pick user, pick level, confirm, done:

![pick user](screenshots/07-priv-user.png)
![pick level](screenshots/08-priv-level.png)
![confirm](screenshots/09-priv-confirm.png)
![done](screenshots/10-priv-done.png)

**`omarchy-change-groups`** — pick user, checklist (preselected), before/after
confirm, done:

![pick user](screenshots/11-groups-user.png)
![checklist](screenshots/12-groups-checklist.png)
![confirm](screenshots/13-groups-confirm.png)
![done](screenshots/14-groups-done.png)

**`omarchy-remove-user`** — pick user, home choice, final confirm, done:

![pick user](screenshots/15-remove-user.png)
![home choice](screenshots/16-remove-home.png)
![confirm](screenshots/17-remove-confirm.png)
![done](screenshots/18-remove-done.png)

## License

MIT — see [LICENSE](LICENSE).
