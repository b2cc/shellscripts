  atlassian-backup.sh - create a backup of an atlassian cloud tenant

  Options:

  generic:
    -h | --help                    display help
    -a | --app [APPNAME]           which cloud app to backup. possible APPNAMEs are:
                                     * bitbucket
                                     * confluence
                                     * jira

    -A | --with-attachments        include attachments in the backup (only valid for confluence and jira)
                                   caution: atlassian allows this only every two days, otherwise backups will fail

    -B | --backup-folder [FOLDER]  location on local filesystem where the backup should be stored

    -t | --tenant [TENANT]         name of the cloud tenant to backup. e.g. if your domain is "https://mycompany.atlassian.net",
                                   the tenant would by "mycompany" (without quotes)

    --print-info                   print some details about the backup process before the backup starts

    --progress-retries [NUMBER]    number of times the script will check if the backup has been prepared. use this value
                                   together with '--progress-sleep' to define maximum interval the script will wait for
                                   the backup to finish (retries * seconds). defaults to 300 retries.

    --progress-sleep [SECONDS]     seconds the script will wait between backup progress checks. defaults to 30 seconds.

    --retention [DAYS]             maximum number of days to keep old backups. defaults to 32 days

    --timezone [TZ]                timezone for correct timestamping of the backup file. defaults to 'Europe/Berlin'

  bitbucket:                       oauth credentials can be created in https://bitbucket.org/<TENANT>/workspace/settings/api

    --oauth-key [KEY]              value of the oauth key set in bitbucket. must at least be able to read projects from bitbucket
    --oauth-secret [SECRET]        value of the oauth secret set in bitbucket.


  confluence/jira:                 API tokens can be defined in https://id.atlassian.com/manage-profile/security/api-tokens
                                   The account needs admin permissions on the atlassian tenant to perform backups

    --api-token [TOKEN]            value of the API token
    --email-address [EMAIL]        corresponding email address of the account that created the API token
