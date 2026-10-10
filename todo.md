# Follow-up work

Open items for maintainer review. Privilege guard changes have a PR open; merged work and that PR's scope are summarized below.

## Account administration

- [ ] Reject root and system accounts (UID < 1000) in `install.sh --add-user`.
- [ ] Define how the installer should update existing accounts. It currently prompts to reset their password unless `--skip-password` is supplied; consider making password changes an explicit opt-in.
- [ ] Explain the privileges granted by `docker` and `input` in the group checklist and confirmation screen.
- [ ] Explain the implications of keeping a removed user's home. A future account assigned the same UID can inherit ownership of those files. Consider offering to archive the home or just transfer ownership to root.

## Documentation

- [ ] Retake `screenshots/02-add-groups.png` and `screenshots/04-add-confirm.png`. They still show `wheel` preselected, although new users now default to no supplementary groups.

## Greeter appearance and usability

Observed on a real install; colour judgments are approximate because the reference images are camera photos.

- [ ] Fix dropdown arrows rendering as blank light squares; the `ComboBox` controls currently have no `arrowIcon`.
- [ ] Remove the doubled password-field border caused by the focus ring and the border baked into `entry.png`.
- [ ] Align the password row with the user/session row.
- [ ] Replace hard-coded Tokyo Night dropdown colours with colours that suit the active Omarchy theme.
- [ ] Review the 700px logo size relative to the login controls.
- [ ] Give the session dropdown enough room for names such as "Omarchy (Hyprland uwsm)" without crowding the arrow or clipping longer names.
- [ ] Label the user and session dropdowns (atop).
- [ ] Fix password cursor alignment: the cursor follows hidden 24px text, while the displayed bullets are 7px images, causing drift as input grows.

## Optional upstream Omarchy feedback

Already documented in `multi-user.md`, section 4:

- [ ] Report that plain users see "Update system" but cannot run it.
- [ ] Report that polkit prompts expect an administrator's password without clearly explaining whose password is required. This is perhaps not that important.
