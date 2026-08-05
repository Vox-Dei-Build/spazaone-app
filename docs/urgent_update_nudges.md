# Urgent update push campaign

`sendUrgentUpdateNudges` runs daily at 08:00 Africa/Johannesburg and targets merchants whose
latest known heartbeat build is below the configured target. Unknown builds
are skipped so the campaign does not guess.

The function reads `systemConfig/urgentUpdateNudges`:

```json
{
  "enabled": true,
  "dryRun": true,
  "targetBuild": 70,
  "targetVersion": "4.1.6",
  "maxPerRun": 500,
  "maxSendsPerUser": 3,
  "cooldownHours": 23,
  "title": "Urgent: update Spaza One today",
  "body": "Don't miss customer messages. Update to {version} now to keep WhatsApp, SMS and conversations working reliably."
}
```

Safe rollout:

1. Deploy only `sendUrgentUpdateNudges`.
2. Create the config above with `dryRun: true`.
3. Run the schedule once and inspect the newest document under
   `systemConfig/urgentUpdateNudges/runs`.
4. Set `dryRun: false`. The next 08:00 run sends the campaign.
5. Set `enabled: false` after the intended campaign window.

Each recipient is re-read immediately before send. Build `70` or newer is
skipped, reminders collapse by target build, invalid tokens are removed, and
the maximum of three daily reminders resets only when a newer target build is
configured.
