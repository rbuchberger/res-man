# Restic Manager (res-man)

[Restic](https://restic.net/) is awesome, but orchestrating it is tricky. Not tricky enough to need a gazillion lines of python, but running it automatically and unattended does present some challenges:

- Backup, check, forget, and prune can all require highly variable lengths of time, should be run on different schedules, and they can't run at the same time.
- You probably want to define multiple backup targets with different schedules and configurations.
- Restic itself needs to be configured through a handful of environment variables and command-line arguments, some of which are secrets.
- You may need to dump databases before the backup, or notify yourself of the results (especially of failures).

`res-man` is a simple, opinionated wrapper that completely solves these problems (for me, anyway).

## Features

- res-man itself is one single file that's shorter than this README and generally readable (for a shell script)
- It has no other dependencies besides restic
- You can easily define multiple jobs/backup targets
- Scheduling is simple: call `res-man myjob daily` once a day.
  - Backup happens every day
  - Check runs weekly
  - Forget & Prune run every 4 weeks (by default) on check day.
  - Operations run sequentially, in a sensible order (backup, forget, prune, check).
- You have easily configurable prepare, on-error, on-success, and on-exit hooks for things like notifications & database dumps.
- Error handling is reasonable:
  - It still tries to complete the backup if the prepare script fails.
  - It still runs the check if something else fails
  - It doesn't try to prune or forget if anything has failed
  - It exits with non-zero status if anything has failed
- You can easily run arbitrary restic commands against your configured repos.

## Installation

1. `# make install`

## Setup

1. Create a new job config: `# res-man <JOB_NAME> scaffold`
2. Edit the job config in `$RESTIC_CONFIG_DIR` (default `/etc/restic`).
    - Add `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, and any other necessary settings/credentials.
3. Configure the backup set using the `include` and `exclude` files
4. (Optional) Add `prepare.sh`, `on-error.sh`, `on-success.sh`, and `on-exit.sh` scripts. They must be executable; don't forget to `chmod +x`.
5. (If required) Initialize repository: `# res-man <JOB_NAME> restic init`
6. (Optional) Run the first backup if you expect it to take a long time. Advisable to do this in a tmux session.
7. Schedule `# res-man <JOB_NAME> daily` via cron or systemd timer (once per day).

## Usage

```sh
res-man <JOB_NAME> <COMMAND>
```

- `JOB_NAME` is the name of the job, which corresponds to the filename in `$RESTIC_CONFIG_DIR`.
- `COMMAND` is one of `daily`, `backup`, `check`, `forget`, `prune`, `scaffold`, or `restic`
  - `daily` - Run backup, then check, then forget, and then prune (in that order, as appropriate).
    - Meant for automatic, scheduled invocation.
    - Check, forget, & prune are only run as scheduled (weekly for check, every 4 weeks for forget & prune).

  - `backup`:

    ```sh
    restic backup \
        --verbose \
        --exclude-caches \
        --one-file-system \
        --files-from "$CONFIG_DIR/${INCLUDE_FILE:-"include"}" \
        --exclude-file "$CONFIG_DIR/${EXCLUDE_FILE:-"exclude"}"
    ```

  - `check` - `restic check --verbose --read-data-subset "${CHECK_SUBSET:-"2%"}"`

  - `prune` - `restic prune --verbose`

  - `forget`:

    ```sh
    restic forget \
        --verbose \
        --keep-last "${KEEP_LAST:-7}" \
        --keep-daily "${KEEP_DAILY:-7}" \
        --keep-weekly "${KEEP_WEEKLY:-4}" \
        --keep-monthly "${KEEP_MONTHLY:-4}"
    ```

    - `scaffold` - Create a new job config with default values.
      - Created in `$RESTIC_CONFIG_DIR` with the name `JOB_NAME`, i.e. `res-man myjob scaffold` will create `/etc/restic/myjob`.
      - Will also add a basic include & exclude file, though you should definitely modify them as required.

    - `restic` - Run any restic command against the configured repo.
      - Example: `res-man myjob restic snapshots`

Examples:

```sh
res-man myjob daily
res-man backblaze backup
res-man synology check
res-man myjob scaffold
res-man myjob restic snapshots

# If you want, you can also just source the config file to work with restic directly:
source /etc/restic/myjob
restic snapshots
restic restore latest --target /tmp/restore
```

## Example Config

### `/etc/restic/myjob`

```sh
export RESTIC_REPOSITORY="sftp:user@host:/path/to/repo"
export RESTIC_PASSWORD="secret_password"

export CHECK_DAY=2 # Check on tuesday instead

# Use custom variables for hooks
export HC_PING_URL="https://hc-ping.com/your-uuid-here"
export NTFY_URL="https://ntfy.sh/mychannel"
```

### `/etc/restic/include`

```
/etc/
/home/
/root/
```

### `/etc/restic/exclude`

```
node_modules
/home/robert/sim/scenery
```

### `/etc/restic/prepare.sh`

- Will receive job name as an argument.
- Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null "$HC_PING_URL"/start &
pacman -Qe >/root/pacman_packages
aur repo -l >/root/aur_repo_packages
```

### `/etc/restic/on-error.sh`

- Will receive the job name and the error message as arguments.
- Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null  "$HC_PING_URL"/fail &
curl -fsS -m 10 --retry 5 -o /dev/null -d "Restic backup job $1 error: $2" "$NTFY_URL" &
```

### `/etc/restic/on-success.sh`

- Will receive the job name as an argument.
- Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null "$HC_PING_URL"/success &
curl -fsS -m 10 --retry 5 -o /dev/null -d "Restic backup job $1 complete" -H "Priority: low" "$NTFY_URL" &
```

## Configuration reference

Global:

- `RESTIC_CONFIG_DIR` - Directory where job configs are stored. Default: `/etc/restic`. All files are specified relative to this directory.

`$RESTIC_CONFIG_DIR`/jobname:

- Applicable [restic config variables](https://restic.readthedocs.io/en/stable/040_backup.html#environment-variables)
- `INCLUDE_FILE` - File containing a list of files/dirs to include in the backup. Default: `include`
- `EXCLUDE_FILE` - File containing a list of files/dirs to exclude from the backup. Default: `exclude`
- `PREPARE_SCRIPT` - Optional executable to run before the backup. Default: `prepare.sh`. Passed jobname as an argument.
- `ON_ERROR` - Optional executable to run when errors occur. Default: `on-error.sh`. Passed jobname & error message as arguments.
- `ON_SUCCESS` - Optional executable to run after a successful backup. Default: `on-success.sh`. Passed jobname as an argument.
- `ON_EXIT` - Optional executable to run after all backups. Default: `on-exit.sh`. Passed jobname as an argument.
- `KEEP_{LAST,DAILY,WEEKLY,MONTHLY}` - Arguments to `restic forget --keep-*`. Default: `7 7 4 12`
- `CHECK_DAY` - Numerical Day of the week to run checks. Default: `1` (Monday)
- `PRUNE_WEEKS` - Forget & Prune every x weeks on check day. Default: `4`.
- `CHECK_SUBSET` - argument to `restic check --read-data-subset`. Default: `2%` (For approximately 100% coverage in a year)

## Roadmap

I made this for me; I'm sharing it because it might be useful to others. I don't plan to add features unless they're useful to me, but I'll accept PRs if they're reasonable.

## Tips & Tricks

- You can define your own variables in job configs and use them in the hook scripts, for example for different notification endpoints.
- [HealthChecks](https://healthchecks.io) is a neat service for monitoring cron jobs (I have no affiliation)
- [ntfy](https://ntfy.sh) is also pretty great. (Also no affiliation)
- You can `source` the job config file and run restic commands directly.

## License

GPLv3
