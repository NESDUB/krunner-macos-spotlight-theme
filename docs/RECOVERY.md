# Recovery and troubleshooting

**Read before overriding a service.** Use ordinary user permissions only.

1. If the manager installed this build and is still intact:
   `python3 tools/manage.py uninstall`.
2. If a managed update failed or looks wrong, try
   `python3 tools/manage.py rollback` (one previous managed binary only).
3. If uninstall refuses due to an edited service/binary, inspect the paths and
   contents shown by `python3 tools/manage.py status` and
   `systemctl --user cat plasma-krunner.service`. Do not blindly delete other
   users' or packages' service drop-ins.
4. For emergency recovery after inspecting that the drop-in contains the
   manager marker `Managed by KRunner Spotlight`, rename *only*
   `~/.config/systemd/user/plasma-krunner.service.d/90-krunner-spotlight.conf`
   to a file outside the `.service.d` folder, then run:

   ```bash
   systemctl --user daemon-reload
   systemctl --user restart plasma-krunner.service
   systemctl --user status plasma-krunner.service --no-pager
   ```

   This leaves the OS packaged KRunner binary unchanged. Other existing
   ExecStart overrides may still control the service. If multiple overrides
   exist, resolve them explicitly; no global settings are silently restored.

Common issues:

- **Refuses Plasma version:** build is pinned to 6.7.5. Newer/older versions
  require an audited and tested new port, not bypassing the version gate.
- **Conflicting override:** inspect `systemctl --user cat plasma-krunner.service`.
  This manager intentionally refuses to supersede an existing ExecStart in
  another drop-in. Legacy `50-custom-interface.conf` must be restored through
  its own original recovery flow first.
- **QML import missing / blank window:** check `journalctl --user -u
  plasma-krunner.service -b --no-pager`; install matching Kirigami, Milou and
  Qt Quick modules. Preserve the native provider plugins.
- **Wrong arch/graphics/backend:** this user build is not relocatable across
  machine architecture, Plasma, or Qt/KF6 ABI revisions.
- **Blur missing:** compositor must support KDE blur regions; Linux cannot use
  macOS private material shaders or SF Symbols.
- **Shortcut doesn't work:** check KRunner shortcut conflicts in KDE settings;
  this package deliberately does not change key mappings.
- **Position wrong:** `FreeFloating` is read from the user's KRunner settings;
  when absent this fork defaults to centered floating. Existing explicit user
  settings are respected and never overwritten by the manager.

- **Start request repeated too quickly:** repeated development restarts can hit
  systemd's start-rate limit. After fixing any actual runtime error, use
  `systemctl --user reset-failed plasma-krunner.service` and then
  `systemctl --user start plasma-krunner.service`. Inspect the journal first;
  repeatedly clearing a genuine crash does not fix its cause.
