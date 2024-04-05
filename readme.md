# Restic Manager (res-man)

[Restic](https://restic.net/) is awesome, but orchestrating it is tricky. Not tricky enough to need a gazillion lines of python, but running it automatically and unattended does present some challenges:

- Backup, check, forget, and prune can all require highly variable lengths of time, should be run on different schedules, and they can't run at the same time.
- You should be able to define multiple backup targets with different schedules and configurations.
- Restic itself is configured through a handful of environment variables and command-line arguments, some of which are secrets.
- You likely need to dump databases before the backup, or notify yourself of the results (especially of failures).

`res-man` is a simple, opinionated wrapper that completely solves these problems (for me, anyway).

## Features

- One single file, ~150 lines of reasonably readable POSIX shell script.
- No other dependencies besides restic
- Easily define multiple jobs/backup targets
- Very simple crontab or systemd timer scheduling: call `res-man myjob daily` once a day.
  - Backup happens every day, check runs weekly, and forget & prune run every 4 weeks (by default) on check day.
  - Operations run in a sensible order and never conflict.
- Reasonable error handling
  - Still tries to complete the backup if prepare script fails.
  - Still runs check if something else fails
  - Doesn't try to prune or forget if anything has failed
  - Exits with non-zero status if anything has failed
- Configurable prepare, on-error, and on-success hooks for things like notifications & database dumps.
- Job configs can be also sourced to run restic commands directly against the configured repo.

## Installation

1. `$ make install` or drop `res-man` in your path.
2. Define jobs in `$RESTIC_CONFIG_DIR`, which is `/etc/restic` by default.
    - The filename is the job name.
    - In the file, export both restic and res-man environment variables. This file will be sourced before running any commands.
    - **Highly recommended to chown the job configs (or anything containing secrets) to root and chmod 600.**
    - Create a list of files/dirs to include and exclude; named `include` and `exclude` by default.

3. Initialize repositories:

    ```sh
    source /etc/restic/myjob
    restic init
    ```

4. Schedule `res-man myjob daily` via cron job or systemd timer.

## Usage

```sh
res-man <JOB_NAME> <COMMAND>
```

- `JOB_NAME` is the name of the job, which corresponds to the filename in `$RESTIC_CONFIG_DIR`.
- `COMMAND` is one of `daily`, `backup`, `check`, `forget`, or `prune`
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

Examples:

```sh
res-man myjob daily
res-man backblaze backup
res-man synology check

# Work with your restic repo directly:
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
```

### `/etc/restic/include`

```
/boot/
/etc/
/home/
/root/
/usr/local/
```

### `/etc/restic/exclude`

```
node_modules
/home/robert/sim/scenery
```

### `/etc/restic/prepare.sh`

Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null https://hc-ping.com/your-uuid-here/start &
pacman -Qe >/root/pacman_packages
aur repo -l >/root/aur_repo_packages
```

### `/etc/restic/on-error.sh`

Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null https://hc-ping.com/your-uuid-here/fail &
curl -fsS -m 10 --retry 5 -o /dev/null -d "Restic backup job $1 error: $2" ntfy.sh/mychannel &
```

### `/etc/restic/on-success.sh`

Don't forget to `chmod +x`

```sh
#!/bin/sh
curl -fsS -m 10 --retry 5 -o /dev/null https://hc-ping.com/your-uuid-here/success &
curl -fsS -m 10 --retry 5 -o /dev/null -d "Restic backup job $1 complete" ntfy.sh/mychannel &
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
- `KEEP_{LAST,DAILY,WEEKLY,MONTHLY}` - Arguments to `restic forget --keep-*`. Default: `7 7 4 12`
- `CHECK_DAY` - Numerical Day of the week to run checks. Default: `1` (Monday)
- `PRUNE_WEEKS` - Forget & Prune every x weeks on check day. Default: `4`.
- `CHECK_SUBSET` - argument to `restic check --read-data-subset`. Default: `2%` (For approximately 100% coverage in a year)

## Roadmap

I made this for me; I'm sharing it because it might be useful to others. I don't plan to add features unless they're useful to me, but I'll accept PRs if they're reasonable.

## License

GPLv3
